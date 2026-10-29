require "rails_helper"

RSpec.describe ApplicationJob, type: :job do
  it "records the changes a job makes as the system actor named after the job" do
    stub_const("PromoteUserJob", Class.new(ApplicationJob) { def perform(user_id) = User.find(user_id).update!(role: "super_admin") })
    user = create(:user)

    PromoteUserJob.perform_now(user.id)

    expect(AuditVersion.where(item_id: user.id, event: "update").sole.whodunnit).to eq("system:PromoteUserJob")
  end
end
