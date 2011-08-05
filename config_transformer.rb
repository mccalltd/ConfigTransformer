#--------------------------------------------------------------------------------------------------
# This utility will do the following:
#   1.  update the target with the default settings in master 
#       (those elements not marked with an "env" attribute or with env="default")
#   2.  update the target with the environment-specific settings in master 
#       (those elements marked with "env" attribute equal to the current environment)
# 
# Notes: 
#   * appSettings/add elements will be matched by the "add" attribute
#   * connectionStrings/add elements will be matched by the "name" attribute
#   * all other elements with "env" attribute will be inserted or will replace existing element
#--------------------------------------------------------------------------------------------------

require 'nokogiri'

class ConfigTransformer

  def initialize(master_config_path, target_config_path, env = "default")
    raise ArgumentError, "master_config_path is required" if master_config_path.nil?
    raise ArgumentError, "target_config_path is required" if target_config_path.nil?

    @master_config_path = master_config_path
    @target_config_path = target_config_path
    @env = env
  end
  
  def execute    
    @master_config = open_xml_doc @master_config_path
    @target_config = open_xml_doc @target_config_path		

    transform_target_to_baseline_with @master_config
    transform_target_to_environment_with @master_config if @env != "default"
    
    write_target
  end
	
private
  def open_xml_doc(path)
    f = File.open path
    doc = Nokogiri::XML(f) {|config| config.strict.noblanks}
    f.close
    doc
  end

  def transform_target_to_baseline_with(node)
    node.children.each do |n|
      # skip environment specific elements or processed elements
      next if (n.attr("env") || "default") != "default"
      next if transform_target_with n
      transform_target_to_baseline_with n
    end
  end

  def transform_target_to_environment_with(node)    
    node.children.each do |n|
      # skip anything not relevent to the current environment or processed elements
      unless n.attr("env") != @env
        next if transform_target_with n
      end
      transform_target_to_environment_with n
    end
  end

  def transform_target_with(node)
    ancestor_names = node.ancestors.map {|a| a.name}
    case
    when ancestor_names.include?("connectionStrings") && node.name == "add" 
      add_to_target node, "[@name='#{node.attr("name")}']"
    when ancestor_names.include?("appSettings") && node.name == "add" 
      add_to_target node, "[@key='#{node.attr("key")}']"
    when node.attr("env") 
      add_to_target node
    else 
      return false # did not process node 
    end
    true # processed node
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
    # remove any "env" attribute that might be on this node
    @target_config.at_xpath(node.path).remove_attribute "env"	
  end

  def ensure_ancestors_exist(node)
    node.ancestors.reverse.each do |n| 
      # skip the root and any existing elements
      next if n.path.eql? "/"		
      next unless @target_config.at_xpath(n.path).nil?
      # append missing element
      parent = n.parent.path ? @target_config.at_xpath(n.parent.path) : @target_config
      parent.add_child n.dup 0
    end
  end

  def write_target
    f = File.open @target_config_path, "w"
    @target_config.write_xml_to(f)
    f.close
  end
end

ConfigTransformer.new("master.config", "web.config", "ci").execute