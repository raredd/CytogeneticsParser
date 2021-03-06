require 'yaml'

module Cytogenetics
  class Aberration

    attr_accessor :breakpoints
    attr_reader :abr, :ab_objs, :fragments

    class<<self
      def instantiate_aberrations
        aberration_obj = {}
        ChromosomeAberrations.constants.each do |ca|
          abr_obj = ChromosomeAberrations.const_get(ca)
          aberration_obj[abr_obj.type.to_sym] = abr_obj
        end
        return aberration_obj
      end
    end

    def self.type
      return @kt
    end

    def self.regex
      return @rx
    end

    def self.all_regex
      rx = {}
      ChromosomeAberrations.constants.each do |ca|
        ca_obj = ChromosomeAberrations.const_get(ca)
        rx[ca_obj.type.to_sym] = ca_obj.regex
      end
      return rx
    end

    # instantiate these
    def self.aberration_objs
      @ab_objs ||= self.instantiate_aberrations
    end

    def self.aberration_type
      abr_breaks = Aberration.all_regex.keys
      abr_breaks.delete_if { |c| c.to_s.match(/gain|loss/) }
      return abr_breaks
    end

    def self.classify_aberration(abr)
      Aberration.all_regex.each_pair do |k, regex|
        return k if abr.match(regex)
      end
      return "unk".to_sym
    end

    def self.chromosome_regex_position
      return @chr_pos ||= 0
    end

    def self.expected_chromosome
      return @ex ||= 1
    end

    def initialize(str, test_bands = true)
      config_logging()

      @abr = str
      @breakpoints = []; @fragments = []

      #regex = Aberration.regex[@type.to_sym]
      # make sure it really is an inversion first
      #raise StructureError, "#{str} does not appear to be a #{self.class}" unless str.match(self.regex)
      begin
        get_breakpoints(test_bands)
      rescue StructureError => e
        @log.warn(e.message)
      end
      @breakpoints.flatten!
    end


    def remove_breakpoint(bp)
      removed = @breakpoints.index(bp)
      @breakpoints.delete_at(removed) if removed
      return removed
    end

    def to_s
      "#{@abr}: #{@breakpoints.join(',')}"
    end

    :private

    def get_breakpoints(test_bands)
      chr_i = find_chr(@abr)
      return if chr_i.nil?

      begin
        band_i = find_bands(@abr, chr_i[:end_index])
        chr_i[:chr].each_with_index do |c, i|
          fragments = find_fragments(band_i[:bands][i])
          fragments.each { |f| @breakpoints << Breakpoint.new(c, f, self.class.type) }
        end
        check_bands() if test_bands
      rescue BandDefinitionError => e
        @log.warn("#{self.class.name} #{e.message}")
        ## No band --> TODO add this as information somewhere but not as a breakpoint
        #@breakpoints << Breakpoint.new(c, "", @type)
      end
    end

    def check_bands
      bands = Cytogenetics.bands.all
      @breakpoints.each do |bp|
        if bands.index(bp.to_s).nil? and bp.to_s.match(/^(\d+|X|Y)([p|q]\d+)\.\d+$/)
          @breakpoints << Breakpoint.new($1, $2) if bands.index("#{$1}#{$2}")
          @log.warn("Band #{bp.to_s} doesn't exist. Removing from breakpoints list.")
        end
      end
      @breakpoints.reject! { |bp|
        reject = bands.index(bp.to_s).nil?
        @log.warn("Band #{bp.to_s} doesn't exist. Removing from breakpoints list.") if reject
        reject
      }
    end

    # Parsing aberration strings to pull out the chromosome and band definitions
    # These will result in breakpoint information
    def find_chr(str)
      chr_s = str.index(/\(/, 0)
      chr_e = str.index(/\)/, chr_s)
      chrs = str[chr_s+1..chr_e-1].split(/;|:/)
      chrs.each do |chr|
        unless chr.match(/^\d+|X|Y$/)
          raise StructureError, "No chromosome defined from #{str}, skipped."
          return
        end
      end
      return {:start_index => chr_s, :end_index => chr_e, :chr => chrs}
    end

    def find_bands(str, index)
      unless str.length.eql?(index+1) # There are no bands
        ei = str.index(/\(/, index)
        if str.match(/(q|p)(\d+|\?)/) and str[ei-1..ei].eql?(")(") # has bands and is not a translocation
          band_s = str.index(/\(/, index)
          band_e = str.index(/\)/, band_s)
          band_e = str.length-1 if band_e.nil?
          bands = str[band_s+1..band_e-1].split(/;|:/)

          if str[band_s+1..band_e-1].match(/::/)
            raise BandDefinitionError, "Aberration defined using unhandled syntax, skipping: #{@abr}"
            #@log.warn("Aberration defined using unhandled syntax, not currently parsed skipping: #{@abr}")
            #return band_info
          else
            bands.map! { |b| b.sub(/-[q|p]\d+$/, "") } # sometimes bands are given a range, for our purposes we'll take the first one (CyDas appears to do this as well)
            bands.each do |b| ## checking the bands
              raise BandDefinitionError, str unless b.match(/^[p|q](\d{1,2})(\.\d{1,2})?$/)
            end
            return {:start_index => band_s, :end_index => band_e, :bands => bands}
          end
        end
      end
      raise BandDefinitionError, str
    end

    # sometimes bands are defined for a single chr as p13q22
    def find_fragments(str)
      return str.scan(/([p|q]\d+)/).collect { |a| a[0] }
    end

    :private

    def config_logging
      @log = Cytogenetics.logger
    end

  end

end