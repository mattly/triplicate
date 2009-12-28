$:.unshift File.dirname(__FILE__) + "/.."

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
      