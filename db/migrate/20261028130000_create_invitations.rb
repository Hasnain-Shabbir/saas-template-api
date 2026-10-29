class CreateInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :invitations, id: :uuid do |t|
      t.citext :email, null: false
      t.string :role, null: false
      t.references :inviter, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify } # kept if the inviter is deleted
      t.string :token_digest # keyed HMAC of the token, never the token. Empty until the email job makes the token, and after use or revoke
      t.datetime :expires_at, null: false
      t.datetime :last_sent_at
      t.datetime :accepted_at
      t.datetime :revoked_at

      t.timestamps
    end

    add_index :invitations, :token_digest, unique: true
    # One open invitation per email. A used or revoked one does not count, so the email can be invited again.
    add_index :invitations, :email, unique: true, where: "accepted_at IS NULL AND revoked_at IS NULL", name: "index_invitations_one_open_per_email"
    add_check_constraint :invitations, "role IN ('super_admin', 'member')", name: "invitations_role_values" # keep in step with users_role_values
    add_check_constraint :invitations, "char_length(email::text) <= 254", name: "invitations_email_length"
    add_check_constraint :invitations, "accepted_at IS NULL OR revoked_at IS NULL", name: "invitations_accepted_or_revoked"
  end
end
