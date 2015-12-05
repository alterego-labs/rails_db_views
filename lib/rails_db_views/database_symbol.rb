class RailsDbViews::DatabaseSymbol
  class CircularReferenceError < RuntimeError; end
  class SymbolNotFound < RuntimeError; end

  attr_accessor :path, :sql_content, :status, :required, :inverse_of_required, :marked_as_deleted, :name
  alias :marked_as_deleted? :marked_as_deleted

  module Status
    LOADED      = :loaded
    IN_PROGRESS = :in_progress
    UNLOADED    = :unloaded
  end

  def initialize file_path
    @path = file_path
    @name = File.basename(file_path, ".*")

    @status = :none
    @required = []
    @marked_as_deleted = false
    @sql_content = File.read(@path)
    @inverse_of_required = []

    load_directives
  end

  def process_inverse_of_required!
    @required.each do |name|
      required = RailsDbViews::Factory.get(self.class, name)
      not_found_error if required.nil?
      required.inverse_of_required << self.name
    end
  end

  def mark_as_delete!
    @marked_as_deleted = true
  end

  def loaded?
    status == Status::LOADED
  end

  def in_progress?
    status == Status::IN_PROGRESS
  end

  def unloaded?
    status == Status::UNLOADED
  end

  def create!
    return if marked_as_deleted? || loaded?

    circular_reference_error if in_progress?

    self.status = Status::IN_PROGRESS

    required.each do |symbol_name|
      symbol = RailsDbViews::Factory.get(self.class, symbol_name)
      not_found_error(symbol_name) if symbol.nil?
      symbol.create!
    end

    ActiveRecord::Base.connection.execute(create_sql)

    self.status = Status::LOADED
  end

  def drop!
    return if loaded?

    circular_reference_error if in_progress?

    self.status = Status::IN_PROGRESS

    # We start by the required one to delete first.
    inverse_of_required.each do |symbol_name|
      symbol = RailsDbViews::Factory.get(self.class, symbol_name)
      not_found_error(symbol_name) if symbol.nil?
      symbol.drop!
    end

    begin
      ActiveRecord::Base.connection.execute(drop_sql)
    # I don't fully understand why catching ActiveRecordError was commented
    # First time when I ran `rake db:migrate` I got the error that said me 'View blabla does not exists'
    # and migration process was crashed.
    rescue ActiveRecord::ActiveRecordError => e #Probably because the symbol doesn't exists yet.
      handle_error_on_drop(e.message)
    end

    self.status = Status::LOADED
  end

  # Theses methods should be implemented in children objects.
  def drop_sql
    raise NotImplementedError, "DatabaseSymbol should not be instanciated"
  end

  def create_sql
    raise NotImplementedError, "DatabaseSymbol should not be instanciated"
  end

  def handle_error_on_drop(error_message)
    raise NotImplementedError, "DatabaseSymbol should not be instanciated"
  end

protected
  TWO_DASH_DIRECTIVE_START = /^--[ \t]*!/
  SHARP_CHAR_DIRECTIVE_START = /^#[ \t]*!/
  DIRECTIVE_START = /#{TWO_DASH_DIRECTIVE_START}|#{SHARP_CHAR_DIRECTIVE_START}/

  def circular_reference_error
    raise CircularReferenceError, "Circular file reference! (file: #{path})"
  end

  def not_found_error(symbol_name)
    raise SymbolNotFound, "#{self.class.name} `#{symbol_name}` referenced in file #{path} cannot be found..."
  end

  def load_directives
    content_lines = sql_content.split("\n")

    directives = content_lines.map(&:strip).select{ |x| x =~ DIRECTIVE_START }.map{ |x|
        x.gsub(DIRECTIVE_START, "")
    }

    directives.each do |d|
      case d
      when /^require /
        self.required += d.split(/[ \t]+/)[1..-1]
      when /^delete(d?) /
        self.mark_as_delete!
      else
        raise IllegalDirective, "I don't know what to do with `#{d}` (in #{path})"
      end
    end

  end

end
