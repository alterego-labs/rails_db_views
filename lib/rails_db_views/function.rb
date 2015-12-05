class RailsDbViews::Function < RailsDbViews::DatabaseSymbol
  def create_sql
    puts "CREATE FUNCTION #{name}..."
    "CREATE FUNCTION #{name}#{sql_content}"
  end

  def drop_sql
    puts "DROP FUNCTION #{name}..."
    "DROP FUNCTION #{name}"
  end

  def handle_error_on_drop(error_message)
    puts "WARNING: DROP FUNCTION #{name}"
    puts "Original error message: #{error_message}"
  end
end
