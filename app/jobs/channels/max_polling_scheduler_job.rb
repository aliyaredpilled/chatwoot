class Channels::MaxPollingSchedulerJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Channel::Max.active.includes(:account).find_each(batch_size: 100) do |channel|
      next unless channel.account.active?

      Channels::MaxPollingJob.perform_later(channel.id)
    end
  end
end
