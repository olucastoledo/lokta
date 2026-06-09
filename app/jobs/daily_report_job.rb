class DailyReportJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Rails.logger.info '[DailyReportJob] Starting daily report checks...'
    Account.find_each do |account|
      timezone = account.reporting_timezone.presence || 'America/Sao_Paulo'
      tz = ActiveSupport::TimeZone[timezone] || Time.zone

      # Check if current local hour is 8
      if tz.now.hour == 8
        Rails.logger.info "[DailyReportJob] Triggering daily report for account #{account.id} (Timezone: #{timezone})"
        DailyReportService.new(account).perform
      end
    end
    Rails.logger.info '[DailyReportJob] Finished daily report checks.'
  end
end
