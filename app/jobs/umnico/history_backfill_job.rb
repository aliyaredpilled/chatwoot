class Umnico::HistoryBackfillJob < ApplicationJob
  queue_as :default

  def perform(conversation, inbox)
    ::Umnico::HistoryBackfillService.new(conversation: conversation, inbox: inbox).perform
  end
end
