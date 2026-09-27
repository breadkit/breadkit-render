# frozen_string_literal: true

module Breadkit
  module Render
    module StateSelection
      module_function

      def resolve(circuit, name)
        refs = name.to_s.split(",")
        return nil if refs.empty? || refs.any?(&:empty?) || refs.uniq.length != refs.length

        switches = circuit.components.values.select { |component| !Array(component.part.data["switch"]).empty? }
        return nil unless (refs - switches.map(&:ref)).empty?

        selected = switches.select { |component| refs.include?(component.ref) }
        closed = selected.flat_map do |component|
          Array(component.part.data["switch"]).map { |pair| [component, pair] }
        end
        Breadkit::State.new(name: selected.map(&:ref).join(","), closed_switches: closed)
      end
    end
  end
end
