class CreateChannelUmnico < ActiveRecord::Migration[7.0]
  def change
    create_table :channel_umnico do |t|
      t.integer :account_id, null: false
      t.string :api_token, null: false
      t.string :webhook_secret
      t.string :webhook_id
      t.integer :umnico_account_id
      t.boolean :enabled, null: false, default: true

      t.timestamps
    end

    add_index :channel_umnico, :api_token, unique: true
    add_index :channel_umnico, :account_id
    add_index :channel_umnico, :enabled
  end
end
