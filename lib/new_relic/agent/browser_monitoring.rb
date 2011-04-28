require 'base64'

module NewRelic
  module Agent
    class BeaconConfiguration
      attr_reader :browser_timing_header
      attr_reader :application_id
      attr_reader :browser_monitoring_key
      attr_reader :beacon
      attr_reader :rum_enabled
      attr_reader :license_bytes

      def initialize(connect_data)
        @browser_monitoring_key = connect_data['browser_key']
        @application_id = connect_data['application_id']
        @beacon = connect_data['beacon']
        @rum_enabled = connect_data['rum.enabled']
        @rum_enabled = true if @rum_enabled.nil?
        @browser_timing_header = build_browser_timing_header(connect_data)
      end

      def license_bytes
        if @license_bytes.nil?
          @license_bytes = []
          NewRelic::Control.instance.license_key.each_byte {|byte| @license_bytes << byte}
        else
          @license_bytes
        end
      end

      def build_browser_timing_header(connect_data)
        return "" if !@rum_enabled
        return "" if @browser_monitoring_key.nil?

        episodes_url = connect_data['episodes_url']
        load_episodes_file = connect_data['rum.load_episodes_file']
        load_episodes_file = true if load_episodes_file.nil?

        load_js = load_episodes_file ? "(function(){var d=document;var e=d.createElement(\"script\");e.type=\"text/javascript\";e.async=true;e.src=\"#{episodes_url}\";var s=d.getElementsByTagName(\"script\")[0];s.parentNode.insertBefore(e,s);})()" : ""

        value = "<script>var NREUMQ=[];NREUMQ.push([\"mark\",\"firstbyte\",new Date().getTime()]);#{load_js}</script>"
        if value.respond_to?(:html_safe)
          value.html_safe
        else
          value
        end
      end
    end

    module BrowserMonitoring

      def browser_timing_header
        return "" if NewRelic::Agent.instance.beacon_configuration.nil?

        return "" if Thread::current[:record_tt] == false || !NewRelic::Agent.is_execution_traced?

        NewRelic::Agent.instance.beacon_configuration.browser_timing_header
      end

      def browser_timing_footer
        config = NewRelic::Agent.instance.beacon_configuration
        return "" if config.nil?
        return "" if !config.rum_enabled
        license_key = config.browser_monitoring_key
        return "" if license_key.nil?

        return "" if Thread::current[:record_tt] == false || !NewRelic::Agent.is_execution_traced?

        application_id = config.application_id
        beacon = config.beacon

        transaction_name = Thread.current[:newrelic_most_recent_transaction] || "<unknown>"
        start_time = Thread.current[:newrelic_start_time]
        queue_time = (Thread.current[:newrelic_queue_time].to_f * 1000.0).round

        value = ''
        if start_time

          obf = obfuscate(transaction_name)
          app_time = ((Time.now - start_time).to_f * 1000.0).round

          queue_time = 0.0 if queue_time < 0
          app_time = 0.0 if app_time < 0

          value = <<-eos
<script type="text/javascript" charset="utf-8">NREUMQ.push(["nrf2","#{beacon}","#{license_key}",#{application_id},"#{obf}",#{queue_time},#{app_time}])</script>
eos
        end
        if value.respond_to?(:html_safe)
          value.html_safe
        else
          value
        end
      end

      private

      def obfuscate(text)
        obfuscated = ""
        key_bytes = NewRelic::Agent.instance.beacon_configuration.license_bytes
        index = 0
        text.each_byte{|byte|
          obfuscated.concat((byte ^ key_bytes[index % 13].to_i))
          index+=1
        }

        [obfuscated].pack("m0").chomp
      end
    end
  end
end