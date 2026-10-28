class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users, id: :uuid do |t|
      t.citext :email, null: false
      t.string :encrypted_password, null: false

      t.timestamps
    end

    add_index :users, :email, unique: true
  end
end
