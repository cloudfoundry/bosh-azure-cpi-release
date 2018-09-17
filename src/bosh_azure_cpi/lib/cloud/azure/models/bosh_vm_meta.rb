# frozen_string_literal: true

module Bosh::AzureCloud
  class BoshVMMeta
    attr_reader :agent_id, :stemcell_cid
    def initialize(agent_id, stemcell_cid)
      @agent_id = agent_id
      @stemcell_cid = stemcell_cid
    end

    def to_s
      "agent_id: #{@agent_id}, stemcell_cid: #{@stemcell_cid}"
    end
  end
end
