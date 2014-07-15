require_relative 'helpers'

module Bosh::AzureCloud
  class StemcellCreator
    include Bosh::Exec
    include Helpers
  end
end