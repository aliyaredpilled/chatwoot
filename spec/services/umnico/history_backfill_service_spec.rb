require 'rails_helper'

describe Umnico::HistoryBackfillService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_widget, account: account)) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: 'umnico:69524567') }
  let(:assignee) { create(:user, account: account, role: :agent) }
  let(:conversation_attrs) do
    {
      'lead_id' => '64951289',
      'umnico_source' => '76919905'
    }
  end
  let(:conversation) do
    create(
      :conversation,
      account: account,
      inbox: inbox,
      contact: contact,
      contact_inbox: contact_inbox,
      assignee: assignee,
      additional_attributes: conversation_attrs
    )
  end
  let(:api_client) { instance_double(Umnico::ApiClient) }
  let(:channel) { instance_double('Channel::Umnico', api_client: api_client) }

  before do
    allow(inbox).to receive(:channel).and_return(channel)
  end

  describe '#perform' do
    it 'imports paginated history in chronological order and preserves reply and attachments' do
      create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        sender: contact,
        message_type: :incoming,
        source_id: 'umnico:11070',
        content: 'current webhook message'
      )

      allow(api_client).to receive(:get_message_history).with('64951289', '76919905', cursor: nil).and_return(
        {
          'cursor' => 123,
          'messages' => [
            {
              'messageId' => '11071',
              'datetime' => 1_711_689_902_000,
              'incoming' => false,
              'sa' => { 'type' => 'telegram' },
              'message' => { 'text' => 'Reply from operator', 'attachments' => [] },
              'replyTo' => {
                'messageId' => '11069',
                'sender' => { 'login' => 'client' },
                'message' => { 'text' => 'Older photo' }
              }
            },
            {
              'messageId' => '11070',
              'datetime' => 1_711_689_901_000,
              'incoming' => true,
              'sa' => { 'type' => 'telegram' },
              'message' => { 'text' => 'Current webhook message', 'attachments' => [] }
            }
          ]
        }
      )
      allow(api_client).to receive(:get_message_history).with('64951289', '76919905', cursor: 123).and_return(
        {
          'cursor' => nil,
          'messages' => [
            {
              'messageId' => '11069',
              'datetime' => 1_711_689_900_000,
              'incoming' => true,
              'sa' => { 'type' => 'telegram' },
              'message' => {
                'attachments' => [
                  {
                    'type' => 'photo',
                    'url' => 'https://example.com/older-photo.jpg'
                  }
                ]
              }
            }
          ]
        }
      )

      described_class.new(conversation: conversation, inbox: inbox).perform

      imported_messages = conversation.reload.messages.where(source_id: %w[umnico:11069 umnico:11071]).reorder(:created_at)
      expect(imported_messages.pluck(:source_id)).to eq(%w[umnico:11069 umnico:11071])

      older_message = conversation.messages.find_by!(source_id: 'umnico:11069')
      newer_message = conversation.messages.find_by!(source_id: 'umnico:11071')

      expect(older_message.message_type).to eq('incoming')
      expect(older_message.sender).to eq(contact)
      expect(older_message.attachments.first.file_type).to eq('image')
      expect(older_message.content_attributes['attachments_meta'].first['url']).to eq('https://example.com/older-photo.jpg')
      expect(older_message.created_at.to_f).to eq(Time.zone.at(1_711_689_900_000 / 1000.0).to_f)

      expect(newer_message.message_type).to eq('outgoing')
      expect(newer_message.sender).to eq(assignee)
      expect(newer_message.content_attributes['reply_to']['messageId']).to eq('11069')
      expect(newer_message.content_attributes['in_reply_to_external_id']).to eq(older_message.id)
    end

    it 'resolves source via get_lead_sources when umnico_source is missing' do
      conversation.update!(additional_attributes: { 'lead_id' => '64951289' })

      allow(api_client).to receive(:get_lead_sources).with('64951289').and_return(
        [{ 'realId' => 888_001 }]
      )
      allow(api_client).to receive(:get_message_history).with('64951289', '888001', cursor: nil).and_return(
        {
          'cursor' => nil,
          'messages' => [
            {
              'messageId' => '22001',
              'datetime' => 1_711_689_903_000,
              'incoming' => true,
              'sa' => { 'type' => 'telegram' },
              'message' => { 'text' => 'Imported through fallback source' }
            }
          ]
        }
      )

      described_class.new(conversation: conversation, inbox: inbox).perform

      expect(api_client).to have_received(:get_lead_sources).with('64951289')
      expect(conversation.reload.messages.find_by(source_id: 'umnico:22001')&.content).to eq('Imported through fallback source')
    end
  end
end
