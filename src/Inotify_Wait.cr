

class Inotify_Wait

  # =============================================================================
  # Class
  # =============================================================================

  def self.run(*args, &blok : Proc(Change, Nil))
    i = new(*args, &blok)
    Signal::INT.trap do
      puts "killing: 0"
      exit 0
    end
    i.loop
    i
  end

  # =============================================================================
  # Instance
  # =============================================================================

  getter proc   : Process
  getter blok   : Proc(Change, Nil)
  getter out_io : IO::Memory = IO::Memory.new
  getter cmd : String

  def initialize(@cmd : String = "-m -r ./ -e close_write", &blok : Proc(Change, Nil))
    @proc = Process.new(
      "inotifywait",
      @cmd.split,
      output: @out_io,
      error: STDERR
    )
    if @proc.terminated?
      exit 2
    end
    @blok = blok
  end

  def kill
    unless proc.terminated?
      puts "=== killing process: #{proc.pid}"
      proc.kill(Signal::INT) 
    end
  end

  def gets_to_end
    return if out_io.empty?
    out_io.rewind
    puts out_io.gets_to_end
  end

  def loop
    at_exit { kill }
    STDERR.puts "=== inotifywait #{cmd}"
    loop {
      if !out_io.empty?
        out_io.rewind
        out_io.each_line { |l|
          @blok.call Change.new(l)
        }
      end

      out_io.clear
      if proc.terminated?
        gets_to_end
        break
      end

      sleep 0.1
    }
    stat = proc.wait
    exit stat.exit_code if stat.normal_exit?
  end

  struct Change

    CONTENT_HISTORY = {} of String => String

    getter dir        : String
    getter event_name : String
    getter file_name  : String
    getter full_path  : String
    getter content    : String
    @is_different : Bool

    def initialize(line : String)
      pieces      = line.split
      if pieces.size != 3
        STDERR.puts line
        exit 1
      end
      @dir        = pieces.shift
      @event_name = pieces.shift
      @file_name  = pieces.shift
      @full_path  = File.join(@dir, @file_name)
      @content    = File.read(@full_path)
      @is_exists  = File.exists?(@full_path)
      @is_different = @content != CONTENT_HISTORY[@full_path]?
        CONTENT_HISTORY[@full_path] = @content
    end # === def initialize

    def exists?
      @is_exists
    end

    def different?
      @is_different
    end

  end # === struct Change

end # === class Inotify

Inotify_Wait.run(ARGV.join(" ")) do |change|
  puts "#{change.full_path} #{change.event_name} #{change.different?}"
  Process.run("uptime", output: STDOUT)
end


