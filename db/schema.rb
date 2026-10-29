# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_29_150001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "pg_catalog.plpgsql"

  create_table "allowlisted_jwts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "jti", null: false
    t.string "aud"
    t.datetime "exp", null: false
    t.uuid "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["jti"], name: "index_allowlisted_jwts_on_jti", unique: true
    t.index ["user_id"], name: "index_allowlisted_jwts_on_user_id"
  end

  create_table "invitations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.citext "email", null: false
    t.string "role", null: false
    t.uuid "inviter_id"
    t.string "token_digest"
    t.datetime "expires_at", null: false
    t.datetime "last_sent_at"
    t.datetime "accepted_at"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_invitations_one_open_per_email", unique: true, where: "((accepted_at IS NULL) AND (revoked_at IS NULL))"
    t.index ["inviter_id"], name: "index_invitations_on_inviter_id"
    t.index ["token_digest"], name: "index_invitations_on_token_digest", unique: true
    t.check_constraint "accepted_at IS NULL OR revoked_at IS NULL", name: "invitations_accepted_or_revoked"
    t.check_constraint "char_length(email::text) <= 254", name: "invitations_email_length"
    t.check_constraint "role::text = ANY (ARRAY['super_admin'::character varying, 'member'::character varying]::text[])", name: "invitations_role_values"
  end

  create_table "onboarding_steps", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.string "step_key", null: false
    t.datetime "completed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "step_key"], name: "index_onboarding_steps_on_user_id_and_step_key", unique: true
    t.check_constraint "char_length(step_key::text) <= 50", name: "onboarding_steps_step_key_length"
  end

  create_table "one_time_codes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.string "purpose", null: false
    t.string "code_digest", null: false
    t.datetime "expires_at", null: false
    t.integer "attempts", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "purpose"], name: "index_one_time_codes_on_user_id_and_purpose", unique: true
    t.check_constraint "attempts >= 0", name: "one_time_codes_attempts_check"
    t.check_constraint "purpose::text = ANY (ARRAY['password_reset'::character varying, 'email_change'::character varying]::text[])", name: "one_time_codes_purpose_check"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.citext "email", null: false
    t.string "encrypted_password", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "failed_attempts", default: 0, null: false
    t.datetime "locked_at"
    t.string "role", default: "member", null: false
    t.citext "pending_email"
    t.citext "previous_email"
    t.string "first_name"
    t.string "last_name"
    t.text "date_of_birth"
    t.text "phone"
    t.string "address_line_1"
    t.string "address_line_2"
    t.string "city"
    t.string "state"
    t.string "postal_code"
    t.string "country"
    t.string "terms_version"
    t.datetime "terms_accepted_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.check_constraint "address_line_1 IS NULL OR char_length(address_line_1::text) >= 1 AND char_length(address_line_1::text) <= 100", name: "users_address_line_1_length"
    t.check_constraint "address_line_2 IS NULL OR char_length(address_line_2::text) >= 1 AND char_length(address_line_2::text) <= 100", name: "users_address_line_2_length"
    t.check_constraint "char_length(email::text) <= 254", name: "users_email_length"
    t.check_constraint "char_length(pending_email::text) <= 254", name: "users_pending_email_length"
    t.check_constraint "char_length(previous_email::text) <= 254", name: "users_previous_email_length"
    t.check_constraint "city IS NULL OR char_length(city::text) >= 1 AND char_length(city::text) <= 100", name: "users_city_length"
    t.check_constraint "country IS NULL OR char_length(country::text) = 2", name: "users_country_length"
    t.check_constraint "first_name IS NULL OR char_length(first_name::text) >= 1 AND char_length(first_name::text) <= 100", name: "users_first_name_length"
    t.check_constraint "last_name IS NULL OR char_length(last_name::text) >= 1 AND char_length(last_name::text) <= 100", name: "users_last_name_length"
    t.check_constraint "postal_code IS NULL OR char_length(postal_code::text) >= 1 AND char_length(postal_code::text) <= 10", name: "users_postal_code_length"
    t.check_constraint "role::text = ANY (ARRAY['super_admin'::character varying, 'member'::character varying]::text[])", name: "users_role_values"
    t.check_constraint "state IS NULL OR char_length(state::text) = 2", name: "users_state_length"
    t.check_constraint "terms_version IS NULL OR char_length(terms_version::text) >= 1 AND char_length(terms_version::text) <= 20", name: "users_terms_version_length"
  end

  add_foreign_key "allowlisted_jwts", "users", on_delete: :cascade
  add_foreign_key "invitations", "users", column: "inviter_id", on_delete: :nullify
  add_foreign_key "onboarding_steps", "users", on_delete: :cascade
  add_foreign_key "one_time_codes", "users", on_delete: :cascade
end
