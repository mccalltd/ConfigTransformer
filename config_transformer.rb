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

def open_xml_doc(path)
	f = File.open path
	doc = Nokogiri::XML(f) do |config|
		config.strict.noblanks
	end
	f.close
	doc
end

@master_config = open_xml_doc("master.config")
@target_config = open_xml_doc("web.config")

def climb_tree(node)
	node.children.each do |n|
		leaf = n
		leaf_name = leaf.name
		
		leaf_type = case
								when branches.include?("appSettings") && leaf_name == "add" then "appSetting"
								when branches.include?("connectionStrings") && leaf_name == "add" then "connectionString"
								else "element"
								end
					 
		#puts "#{leaf_name} (#{leaf_type}): #{branches.join(' ')}"
		
		if leaf_type == "appSetting"
			update_app_setting leaf
		end
		
		climb_tree n
	end
end

def baseline_target(node)
	node.children.each do |n|						
		node_name = n.name
		node_type = node_type(n)
		
		unless n.attr "env"		
			update_app_setting(n) if node_type == :appSetting
			update_connection_string(n) if node_type == :connectionString
		end
		
		baseline_target n
	end
end

def node_type(node)
	branches = node.ancestors
								 .map {|a| a.name}
								 .reverse
								 .delete_if {|a| %w{document comment}.include?(a)}
	case
	when branches.include?("appSettings") && node.name == "add" then :appSetting
	when branches.include?("connectionStrings") && node.name == "add" then :connectionString
	else :element
	end
end

def update_app_setting(master_node)
	target_node = @target_config.at_css("appSettings add[key='#{master_node.attr("key")}']")
	if target_node
		target_node.replace(master_node) 
	else
		@target_config.at_css("appSettings").add_child(master_node)
	end
end

def update_connection_string(master_node)
	puts master_node
	target_node = @target_config.at_css("connectionStrings add[name='#{master_node.attr("name")}']")
	if target_node
		target_node.replace(master_node) 
	else
		@target_config.at_css("connectionStrings").add_child(master_node)
	end
end

baseline_target @master_config

f = File.open("web.config", "w")
@target_config.write_xml_to(f)
f.close