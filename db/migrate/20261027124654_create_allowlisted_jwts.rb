class CreateAllowlistedJwts < ActiveRecord::Migration[8.1]
  def change
    create_table :allowlisted_jwts, id: :uuid do |t|
      t.string :jti, null: false
      t.string :aud
      t.datetime :exp, null: false
      t.references :user, type: :uuid, null: false, foreign_key: { on_delete: :cascade }

      t.timestamps
    end

    add_index :allowlisted_jwts, :jti, unique: true
  end
end
