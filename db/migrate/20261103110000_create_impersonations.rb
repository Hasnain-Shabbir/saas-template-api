# The impersonation log: which super_admin acted as which user, why, and for how long (HIPAA "who accessed whose account").
# One row per session. It is only ever added to; the single allowed change is to end it once (`ended_at` and `ended_reason`).
# The foreign keys use RESTRICT on purpose: a user who was impersonated or who impersonated cannot be deleted while the row exists.
# `jti` ties the row to the token's allowlist row, which is deleted when the session ends. It has no foreign key for that reason.
# The partial unique index is the rule "one open session per admin". A session that ran out is closed by the service before a new one starts.
class CreateImpersonations < ActiveRecord::Migration[8.1]
  def change
    create_table :impersonations, id: :uuid do |t|
      t.references :impersonator, null: false, type: :uuid, index: false, foreign_key: { to_table: :users, on_delete: :restrict }
      t.references :target, null: false, type: :uuid, index: false, foreign_key: { to_table: :users, on_delete: :restrict }
      t.string :jti, null: false
      t.string :reason_category, null: false # "support_request", "bug_investigation", "data_correction", "security_investigation", "other"
      t.text :reason # a note; required when the category is "other". Never personal data.
      t.string :request_id
      t.datetime :started_at, null: false
      t.datetime :expires_at, null: false
      t.datetime :ended_at
      t.string :ended_reason # "stopped", "expired", or "ended_by_system"
    end

    add_index :impersonations, :jti, unique: true
    add_index :impersonations, :impersonator_id, unique: true, where: "ended_at IS NULL", name: "index_impersonations_one_open_per_impersonator"
    add_index :impersonations, [ :impersonator_id, :started_at ]
    add_index :impersonations, [ :target_id, :started_at ]
    add_index :impersonations, :started_at

    add_check_constraint :impersonations, "impersonator_id <> target_id", name: "impersonations_not_self"
    add_check_constraint :impersonations, "expires_at > started_at", name: "impersonations_expires_after_start"
    add_check_constraint :impersonations, "(ended_at IS NULL) = (ended_reason IS NULL)", name: "impersonations_end_fields_together"
    add_check_constraint :impersonations, "ended_reason IN ('stopped', 'expired', 'ended_by_system')", name: "impersonations_ended_reason_values"
    add_check_constraint :impersonations, "reason_category IN ('support_request', 'bug_investigation', 'data_correction', 'security_investigation', 'other')", name: "impersonations_reason_category_values"
    add_check_constraint :impersonations, "reason IS NULL OR char_length(btrim(reason)) BETWEEN 1 AND 500", name: "impersonations_reason_length"
    add_check_constraint :impersonations, "reason_category <> 'other' OR reason IS NOT NULL", name: "impersonations_other_needs_reason"
    add_check_constraint :impersonations, "char_length(jti) <= 100", name: "impersonations_jti_length"
    add_check_constraint :impersonations, "char_length(request_id) <= 255", name: "impersonations_request_id_length"
  end
end
