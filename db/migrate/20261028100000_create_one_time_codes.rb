class CreateOneTimeCodes < ActiveRecord::Migration[8.1]
  def change
    create_table :one_time_codes, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :purpose, null: false
      t.string :code_digest, null: false # keyed HMAC of the code, never the code itself
      t.datetime :expires_at, null: false
      t.integer :attempts, null: false, default: 0

      t.timestamps
    end

    # One live code per user and purpose: a new code replaces the old one. The user_id lead also serves the foreign key.
    add_index :one_time_codes, [ :user_id, :purpose ], unique: true
    add_check_constraint :one_time_codes, "purpose IN ('password_reset')", name: "one_time_codes_purpose_check"
    add_check_constraint :one_time_codes, "attempts >= 0", name: "one_time_codes_attempts_check"
  end
end
