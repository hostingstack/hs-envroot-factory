module EnvRootFactory
  class BuildRootJob < Resque::JobWithStatus
    def perform
      job_desc = BuildRootJobDescription.new
      job_desc.job_token = options["job_token"]
      job_desc.app_code_url = options["app_code_url"]
      job_desc.dest_env_root_url = options["dest_env_root_url"]
      job_desc.prev_recipe_hash = options["prev_recipe_hash"]
      job_desc.prev_env_root_url = options["prev_env_root_url"]
      job_desc.facts = options["facts"]
      job_desc.service_config = options["service_config"]
      job_desc.force_from_scratch = options["force_from_scratch"]

      reply = Cook.new(job_desc).run { |msg| tick msg }
      completed({:fields => reply})
    end
  end

  class BuildRootJobDescription
    attr_accessor :job_token, :app_code_url, :dest_env_root_url, :prev_recipe_hash, :prev_env_root_url, :facts, :service_config, :force_from_scratch
  end
end

