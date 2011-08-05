#--------------------------------------------------------------------------------------------------
# This utility will do the following:
# 	1. 	update the target with the default settings in master 
#		 		(those elements not marked with an "env" attribute or with env="default")
# 	2. 	update the target with the environment-specific settings in master 
#		 		(those elements marked with "env" attribute equal to the current environment)
# 
#	Notes: 
# 	* appSettings/add elements will be matched by the "add" attribute
# 	* connectionStrings/add elements will be matched by the "name" attribute
# 	* all other elements with "env" attribute will be inserted or will replace existing element
#--------------------------------------------------------------------------------------------------

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

	def baseline_target_with(node)
		node.children.each do |n|								
			env = n.attr("env") || "default"
			next if env != "default"
			
			ancestor_names = n.ancestors.map {|a| a.name}
			case
			when ancestor_names.include?("connectionStrings") && n.name == "add" 
				update_connection_string_with n 
			when ancestor_names.include?("appSettings") && n.name == "add" 
				update_app_setting_with n
			when node.attr("env") 
				update_element_with n 
				next
			end
			
			baseline_target_with n
		end
	end

	def update_connection_string_with(node)
		add_to_target node, "[@name='#{node.attr("name")}']"
	end

	def update_app_setting_with(node)
		add_to_target node, "[@key='#{node.attr("key")}']"
	end

	def update_element_with(node)		
		add_to_target node
		
		replacement_node = @target_config.at_xpath node.path
		replacement_node.remove_attribute "env"	
	end

	def ensure_ancestors_exist(node)
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
	end
	
	def add_to_target(node, attr_selector = nil)
		# not sure why the given node has an index in its path -- need to strip it
		target_node = @target_config.at_xpath "#{node.path.gsub(/\[.*?\]$/, "")}#{attr_selector}"
		if target_node.nil?
			ensure_ancestors_exist node
			@target_config.at_xpath(node.parent.path).add_child node
		else
			target_node.replace node
		end
	end

	def write_xml_to_target
		f = File.open @target_config_path, "w"
		@target_config.write_xml_to(f)
		f.close
	end
end

c = ConfigTransformer.new 
c.master_config_path = "master.config"
c.target_config_path = "web.config"
c.execute