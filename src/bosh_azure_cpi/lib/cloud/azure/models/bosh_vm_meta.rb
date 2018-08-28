# frozen_string_literal: true

module Bosh::AzureCloud
  class BoshVMMeta
    attr_reader :agent_id, :stemcell_id
    def initialize(agent_id, stemcell_id)
      @agent_id = agent_id
      @stemcell_id = stemcell_id
    end

    def to_s
      "agent_id: #{@agent_id}, stemcell_id: #{@stemcell_id}"
    end
  end
end
