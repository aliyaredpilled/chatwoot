class CreateChannelMax < ActiveRecord::Migration[7.0]
  def change
    create_table :channel_max do |t|
      t.integer :account_id, null: false
      t.string :bot_name
      t.string :bot_token, null: false
      t.boolean :enabled, null: false, default: true
      t.bigint :last_event_marker
      t.integer :polling_interval_seconds, null: false, default: 20
      t.jsonb :user_chat_map, null: false, default: {}

      t.timestamps
    end

    add_index :channel_max, :bot_token, unique: true
    add_index :channel_max, :account_id
    add_index :channel_max, :enabled
  end
end
