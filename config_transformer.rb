#---------------------------------------------------------------------------------------
# This utility will do the following:
# 	1. 	update the target with the default settings in master 
#		 		(those elements not marked with an "env" attribute)
# 	2. 	update the target with the environment-specific settings in master 
#		 		(those elements marked with "env" attribute equal to the current environment)
# 
#	Notes: 
# 	* appSettings/add elements will be matched by the "add" attribute
# 	* connectionStrings/add elements will be matched by the "name" attribute
# 	* all other elements will be matched by the element itself
#---------------------------------------------------------------------------------------

require 'nokogiri'

class ConfigTransformer
	attr_accessor :master_config_path, :target_config_path
	
	def initialize
	end

	def execute
		raise ArgumentError, "master_config_path is required" if @master_config_path.nil?
		raise ArgumentError, "target_config_path is required" if @target_config_path.nil?
		
		@master_config = open_xml_doc @master_config_path
		@target_config = open_xml_doc @target_config_path		

		baseline_target_with @master_config
		
		write_xml_to_target
	end
	
private
	def open_xml_doc(path)
		f = File.open path
		doc = Nokogiri::XML(f) do |config|
			config.strict.noblanks
		end
		f.close
		doc
	end

	def write_xml_to_target
		f = File.open @target_config_path, "w"
		@target_config.write_xml_to(f)
		f.close
	end
	
	def baseline_target_with(node)
		node.children.each do |n|								
			env = n.attr("env") || "default"
			next if env != "default"
			
			case type_of_node n
			when :appSetting
				update_app_setting_with n
			when :connectionString
				update_connection_string_with n 
			when :element
				update_element_with n 
				next
			end
			
			baseline_target_with n
		end
	end

	def type_of_node(node)
		ancestor_names = node.ancestors.map {|a| a.name}
		case
		when ancestor_names.include?("appSettings") && node.name == "add" 
			:appSetting
		when ancestor_names.include?("connectionStrings") && node.name == "add" 
			:connectionString
		when node.attr("env") 
			:element
		end
	end

	def update_app_setting_with(node)
		@target_config.add_child Nokogiri::XML::Node.new "appSettings", @target_config if @target_config.at_xpath("//appSettings").nil?
		target_node = @target_config.at_xpath "//appSettings/add[@key='#{node.attr("key")}']"
		if target_node
			target_node.replace node
		else
			@target_config.at_xpath("//appSettings").add_child node
		end
	end

	def update_connection_string_with(node)
		@target_config.add_child Nokogiri::XML::Node.new "connectionStrings", @target_config if @target_config.at_xpath("//connectionStrings").nil?
		target_node = @target_config.at_xpath("//connectionStrings/add[@name='#{node.attr("name")}']")
		if target_node
			target_node.replace node 
		else
			@target_config.at_xpath("//connectionStrings").add_child node
		end
	end

	def update_element_with(node)
		# create necessary ancestor elements
		node.ancestors.reverse.each do |n| 
			# skip the root
			next if n.path.eql? "/"		
			# skip unless the current ancestor is not in the target config
			next unless @target_config.at_xpath(n.path).nil?
			# find the parent of the missing element
			parent = n.parent.path ? @target_config.at_xpath(n.parent.path) : @target_config
			# append the missing element
			parent.add_child n.dup 0
		end
		
		# the replacement node will be the given node minus any env attribute
		replacement_node = node.dup
		replacement_node.remove_attribute "env"	
		
		# the target will be the given node's twin in the target if it exists;
		# otherwise the target will be the given node's parent in the target
		target_node = @target_config.at_xpath node.path
		if target_node.nil?
			@target_config.at_xpath(node.parent.path).add_child replacement_node
		else
			target_node.replace replacement_node
		end
	end
end

c = ConfigTransformer.new 
c.master_config_path = "master.config"
c.target_config_path = "web.config"
c.execute