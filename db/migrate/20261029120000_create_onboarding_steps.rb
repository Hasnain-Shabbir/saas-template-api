class CreateOnboardingSteps < ActiveRecord::Migration[8.1]
  def change
    create_table :onboarding_steps, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, index: false, foreign_key: { on_delete: :cascade } # progress means nothing without the user
      t.string :step_key, null: false # a key from Onboarding::Registry. Not a CHECK list: projects add steps in code, without a migration
      t.datetime :completed_at, null: false

      t.timestamps
    end

    # One row per user and step. This also serves the lookup by user (the first column), so there is no separate user_id index.
    add_index :onboarding_steps, [ :user_id, :step_key ], unique: true
    add_check_constraint :onboarding_steps, "char_length(step_key) <= 50", name: "onboarding_steps_step_key_length" # keep in step with ValidationRules::ONBOARDING_STEP_KEY_MAX_LENGTH
  end
end
