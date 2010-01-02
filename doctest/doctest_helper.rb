$:.unshift File.dirname(__FILE__) + "/.."
begin
  require 'ruby-debug'
rescue nil
end

require 'lib/triplicate'

class Proc
  def raises_error?(err=StandardError)
    raised = false
    begin
      self.call
    rescue Exception => e
      if e.is_a? err
        raised = true
      end
    end
    raised
  end
end
      