class AddGmailAddressToUser < ActiveRecord::Migration
  def change
    add_column :users, :gmail_address, :text
  end
end
