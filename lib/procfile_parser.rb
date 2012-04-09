class ProcfileParser
  def self.parse!(procfile_data)
    entries = {}
    begin
      procfile_data.split("\n").each do |line|
        line.strip!
        next if line == ""
        next if line.start_with?('#')
        name, command = line.split(/\s*:\s+/, 2)
        next if name.nil? or command.nil? or command.empty?
        entries[name] = command
      end
    rescue => e
      raise
    end
    entries
  end
end
