require 'sketchup.rb'
require 'extensions.rb'

module LeonardoLabs
  module PlanForgeBuilder
    EXTENSION_NAME = 'PlanForge Builder'.freeze unless const_defined?(:EXTENSION_NAME)
    EXTENSION_VERSION = '0.3.0'.freeze unless const_defined?(:EXTENSION_VERSION)
    LOADER_PATH = 'planforge_builder/main'.freeze unless const_defined?(:LOADER_PATH)
  end
end

unless file_loaded?(__FILE__)
  extension = SketchupExtension.new(
    LeonardoLabs::PlanForgeBuilder::EXTENSION_NAME,
    LeonardoLabs::PlanForgeBuilder::LOADER_PATH
  )
  extension.description = 'Fast wall and room sketching workflow for architectural massing.'
  extension.version = LeonardoLabs::PlanForgeBuilder::EXTENSION_VERSION
  extension.creator = 'LeonardoLabs'
  extension.copyright = '2026 LeonardoLabs'

  Sketchup.register_extension(extension, true)
  file_loaded(__FILE__)
end
