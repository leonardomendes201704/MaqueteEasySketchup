require 'fileutils'

module LeonardoLabs
  module PlanForgeBuilder
    module Diagnostics
      extend self

      def log_path
        @log_path ||= begin
          base = ENV['LOCALAPPDATA'] || ENV['TEMP'] || ROOT
          folder = File.join(base, 'PlanForgeBuilder')
          FileUtils.mkdir_p(folder)
          File.join(folder, 'planforge_builder.log')
        end
      end

      def write(message)
        File.open(log_path, 'a') do |file|
          file.puts("[#{timestamp}] #{message}")
        end
        nil
      rescue StandardError
        nil
      end

      def error(context, error)
        backtrace = Array(error.backtrace).first(10).join("\n")
        write("ERROR #{context}: #{error.class}: #{error.message}\n#{backtrace}")
      end

      private

      def timestamp
        Time.now.strftime('%Y-%m-%d %H:%M:%S')
      end
    end
  end
end
