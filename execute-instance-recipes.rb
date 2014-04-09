
require 'rubygems'
require 'json'

def usage
  puts 'Usage: execute-instance-recipes.rb <layer-id> <recipes> [\'custom-json\']'
  puts
  puts 'Runs recipes on all online instances in a layer, and reports their success via shell status_code.'
  puts
  puts 'layer-id:    The OpsWorks Layer ID where the instances are located.'
  puts 'recipes:     JSON array of recipes to run, in the format of: \'["cookbook::recipe"]\'. Wrap in single quotes.'
  puts 'custom-json: Custom JSON to use for the deployment. Wrap in single quotes.'
  exit 1
end

unless `which aws`
  puts 'awscli not found!'
  usage
end

args = ARGV.dup

# flag check
if args.include? '--single'
  args.delete '--single'
  SINGLE_INSTANCE = true
else
  SINGLE_INSTANCE = false
end

if args.length < 2
  usage
end

layer_id = args[0]
recipes = args[1]
custom_json = args[2].nil? ? '' : args[2]

# all instances in layer
instances_command = %|aws opsworks describe-instances --layer-id #{layer_id}|
instances = JSON.parse(`#{instances_command}`)['Instances']
if instances.empty?
  puts "Failed to load instances."
  puts "Command: #{instances_command}"
  exit 1
end
# that are online
instances.delete_if {|x| x['Status'] != 'online' }
# pluck their ids
instance_ids = instances.collect {|x| x['InstanceId'] }
print 'Found online instances: '
p instance_ids
if SINGLE_INSTANCE
  instance_ids = instance_ids.take 1
  print 'As requested, will only run on a single instance: '
  p instance_ids
end

# Find the Stack ID by validating the Layer
layer_command = %|aws opsworks describe-layers --layer-ids #{layer_id}|
layer = JSON.parse(`#{layer_command}`)['Layers'].first
if layer.nil?
  puts "Layer '#{layer_id}' was not found!"
  exit 1
end
stack_id = layer['StackId']
print 'Found layer with a Stack ID: '
p stack_id

puts 'Creating OpsWorks deployment.'
print 'Using recipes: '
p recipes
unless custom_json.empty?
  print 'Using custom JSON: '
  p custom_json
end

# kick off the publish recipe
publish_command = %|aws opsworks create-deployment --stack-id #{stack_id} --instance-ids #{instance_ids.join(' ')} --command='{"Name": "execute_recipes", "Args": {"recipes": #{recipes}}}'|
unless custom_json.empty?
  publish_command += %| --custom-json='#{custom_json}'|
end
results = `#{publish_command}`
publish_id = JSON.parse(results)['DeploymentId']
if publish_id.empty?
  puts "Failed to create publish recipe deploy."
  puts "Command: #{publish_command}"
  exit 1
end
print 'Deployment ID received: '
p publish_id

status_command = %|aws opsworks describe-deployments --deployment-ids #{publish_id}|
start_time = Time.now
max_time = start_time + 3600
while Time.now < max_time
  # sleep first to give it time to run
  sleep 5
  print "(#{(Time.now - start_time).round} secs) Checking status... "
  results = `#{status_command}`
  unless results.empty?
    status = JSON.parse(results)['Deployments'][0]['Status']

    if status == 'successful'
      puts "deployment was successful."
      exit 0
    elsif status == 'failed'
      puts "deployment failed!"
      exit 1
    else
      puts status
    end
  end
end

puts "Deployment '#{publish_id}' on instances #{instance_ids} took over an hour, giving up."
exit 1
