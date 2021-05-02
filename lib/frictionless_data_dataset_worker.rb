# encoding: utf-8

module Bionomia
  class FrictionlessDataDatasetWorker
    include SuckerPunch::Job

    def perform(data)
      ActiveRecord::Base.connection_pool.with_connection do
        fd = FrictionlessDataDataset.new(data)
        fd.create_package
      end
    end

  end
end
