# Parameters loading
require 'yaml'
config = YAML.load_file('config.yaml')
debug        = config["debug"] || false
replaced_tag = config["replaced_tag"] || ' // __REPLACED'
renamed_tag  = config["renamed_tag"]  || ' // __RENAMED'
functions    = config["functions"] || {}
variables    = config["variables"] || {}
replaced_tag_empty = replaced_tag.empty? && (replaced_tag = ' // __EMPTY')

# Constants
eol = $/
before_after_id = Regexp.escape(' ,()[]{}?')
before_id = '(?<=(?:[' + before_after_id + Regexp.escape('!') + '])|(?:^))'
after_id  = '(?=(?:[' + before_after_id + Regexp.escape('.;') + '])|(?:$))'

# Intro (echo 100 blank lines)
100.times { puts '' } if debug

# Read ga-beautified.js file
ga = File.read('ga-beautified.js')

# Replace variables by values
puts 'Replaced variables :' if debug
ga.clone.scan(/(^(?:(?:    var )|(?:        ))(\w+) = ((?:\w+)|(?:"\w+")|(?:void 0)|(?:!\d))[,;]?$)/i) do |statement, name, value|

    # Exclude counters
    next if value == '0'

    # Readable keywords
    case value
        when 'void 0' then value = 'undefined'
        when '!0'     then value = 'true'
        when '!1'     then value = 'false'
    end

    # Replacement
    ga.gsub!(/#{statement}/, statement + replaced_tag)
    ga.gsub!(/#{before_id}#{name}#{after_id}(?!.*#{replaced_tag}$)/, value)
    ga.gsub!(replaced_tag, '') if replaced_tag_empty
    puts "  #{name} => #{value}" if debug

end

# Rename function and parameter
puts 'Renamed functions :' if debug
functions.each do |old_name, new_name|

    # Process parameters ?
    new_parameters = new_name.slice(/\w+\s*\(\s*(.*)\s*\)/, 1)
    unless new_parameters.nil?
        new_parameters = new_parameters.split(/\s*,\s*/)
        new_parameters = nil if new_parameters.length.zero?
        new_name = new_name.slice(/(\w+)\s*\(/, 1)
    end

    # Process function declaration
    pattern = /^(\s*)((?:(?:var |\},)?\s*#{old_name} = (?:new )?function \()|(?:function #{old_name}\())(.*)(\) \{\}?$)/
    indent = ''
    old_parameters = nil
    do_rename_parameters = false
    ga_new = ''
    ga.each_line do |line|

        # Declaration header
        if m = line.sub(/ function /i, ' function ').match(pattern)
            line.chomp!

            # Rename parameters
            unless new_parameters.nil?
                # Store old parameters
                indent = m[1]
                old_parameters = m[3].split(/\s*,\s*/)
                if new_parameters.length != old_parameters.length
                    puts "!!! ERROR !!! Parameters can't be renamed for function #{new_name} : #{new_parameters.length} instead of #{old_parameters.length} (invalid parameter count)"
                    new_parameters = nil
                else
                    do_rename_parameters = true
                    line = line.sub(pattern, "\\1\\2#{new_parameters.join(', ')}\\4")
                end
            end

            # Add tag
            line = line << renamed_tag << eol

        # Declaration body
        elsif do_rename_parameters
            # Rename parameters inside body
            if line.start_with?(indent + ' ')
                new_parameters.each_index do |i|
                    line.gsub!(/#{before_id}#{old_parameters[i]}#{after_id}/, new_parameters[i]) if old_parameters[i] != new_parameters[i]
                end
            # End of declaration
            else
                do_rename_parameters = false
            end
        end

        ga_new << line

    end
    ga = ga_new

    # Rename function in all occurrences
    ga.gsub!(/#{before_id}#{old_name}#{after_id}/, new_name) if old_name != new_name
    if debug
        unless new_parameters.nil? or old_parameters.nil?
            puts "  #{old_name}(#{old_parameters.join(', ')}) => #{new_name}(#{new_parameters.join(', ')})"
        else
            puts "  #{old_name} => #{new_name}"
        end
    end

end

# Rename variables
puts 'Renamed variables :' if debug
variables.each do |old_name, new_name|

    # Rename
    # TODO Add rename tag
    ga.gsub!(/#{before_id}#{old_name}#{after_id}/, new_name)
    puts "  #{old_name} => #{new_name}" if debug

end

# Rename $ methods
puts 'Rename $ methods:' if debug
dollar_begin = Regexp.escape('    var $ = function () {')
dollar_end   = Regexp.escape('    };')
dollar_replaced = []
ga.clone.slice(/^#{dollar_begin}$#{eol}(.*?)#{eol}^#{dollar_end}$/m, 1).each_line do |line|

    # Process Qc & V function
    if m = line.match(/^\s*(?:Qc|V)\("(\w+)", (\w+),/)

        # Do not process '$...' variables
        next if m[2].start_with?('$')

        # Do not process same variables twice
        next if dollar_replaced.include?(m[2])

        # Add tag
        ga.gsub!(Regexp.new(Regexp.escape(line.chomp)), line.chomp + renamed_tag)

        # Rename
        old_var = m[2]
        new_var = '_' + m[1].slice(/^_(?:[gs]et)?(\w+)/, 1).sub(/^[A-Z]/) {|c| c.downcase }
        ga.gsub!(/#{before_id}#{old_var}#{after_id}/, new_var)
        dollar_replaced << old_var
        puts "  #{old_var} => #{new_var}" if debug

    end

end

# Replace scientific notation
puts 'Replaced scientific notation :' if debug
ga.gsub!(/#{before_id}\d+(?i:E)\d+#{after_id}/) do |scientific|
    standard = scientific.to_f.to_i
    puts "  #{scientific} => #{standard}" if debug
    standard
end

# Make readable function calls
# a["indexOf"](b) => a.indexOf(b)
puts 'Readable function calls :' if debug
ga.gsub!(/\["(\w+)"]\(/) do |old_call|
    new_call = ".#{$1}("
    puts "  #{old_call} => #{new_call}" if debug
    new_call
end

# Write result to gae-automatic.js
File.open('gae-automatic.js', 'w') do |out|
    out << ga
end

# Outro
puts '' if debug
puts 'Done !'
