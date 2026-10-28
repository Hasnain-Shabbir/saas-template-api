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

ActiveRecord::Schema[8.1].define(version: 2026_10_28_120004) do
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
    t.index ["email"], name: "index_users_on_email", unique: true
    t.check_constraint "char_length(email::text) <= 254", name: "users_email_length"
    t.check_constraint "char_length(pending_email::text) <= 254", name: "users_pending_email_length"
    t.check_constraint "char_length(previous_email::text) <= 254", name: "users_previous_email_length"
    t.check_constraint "role::text = ANY (ARRAY['super_admin'::character varying, 'member'::character varying]::text[])", name: "users_role_values"
  end

  add_foreign_key "allowlisted_jwts", "users", on_delete: :cascade
  add_foreign_key "one_time_codes", "users", on_delete: :cascade
end
