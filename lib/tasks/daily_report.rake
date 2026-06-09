namespace :reports do
  desc 'Send daily report to webhook'
  task :daily, [:account_id, :date] => :environment do |_t, args|
    account_id = args[:account_id]
    date_str = args[:date]

    if account_id.blank?
      puts 'Usage: bundle exec rails reports:daily[account_id,date]'
      puts 'Example: bundle exec rails reports:daily[2] (for yesterday)'
      puts 'Example: bundle exec rails reports:daily[2,2026-06-08] (for a specific date)'
      exit 1
    end

    account = Account.find_by(id: account_id)
    if account.nil?
      puts "Error: Account with ID #{account_id} not found."
      exit 1
    end

    puts "Generating and sending daily report for Account #{account.id} (#{account.name})..."
    puts "Date: #{date_str || 'Yesterday'}"

    service = DailyReportService.new(account, date_str)

    # Print the text report to the terminal
    puts "\n--- REPORT TEXT ---"
    puts service.generate_report_text
    puts "-------------------\n"

    success = service.perform
    if success
      puts 'Success: Webhook sent successfully!'
    else
      puts 'Warning: Webhook failed to send or is not configured.'
    end
  end
end
