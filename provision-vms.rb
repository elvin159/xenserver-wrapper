#!/usr/bin/env ruby
#
# Context: Script to build VMs in xenserver pools while abstracting the chef objects and making it entirely menu driven
# Date: 20130924
# Created by: Elvin Abordo
# Email: elvin.abordo@mindspark.com
#
# this is required to parse IP addresses and verify they're formatted correctly
require 'ipaddr'
# this is require in order to pass system commands to the console
require 'io/console'
# this does all the menu driving 
require 'highline/import'
# this is to obtain the IP address of the hostname entered
require 'resolv'

puts "*******************"
puts "*******************"
puts "Please visit http://confluence.iaccap.com/display/ITSYS/Chef+-+How+to+create+VMs+from+lvsysinfra1"
puts "*******************"
puts "*******************"


# User needs to have DNS entries created otherwise a failed DNS lookup will fail from the start

hostname = ask("Hostname? ") { |h| h.default ="none" }

ip = Resolv.getaddress(hostname)
ip = IPAddr.new(ip).to_s

nm = ask("What is the NETMASK of #{ip} ? ") { |m| m.default="255.255.255.0"}

gw = ask("What is the GATEWAY of #{ip} ? ") { |p| p.default="10.90.0.1"}
gw = IPAddr.new(gw)


puts "Please wait while gathering a list of VLANs to choose from ..."

# Executing a system command to generate a list of VLANS to choose from
# This really should just be done via an API call to the xenserver make it faster
# But alas it will be on a TODO list for an infinite amount of time

vlan = `knife xenserver network list |grep VLAN | awk '{ print$2, $3}' | sort`
vlan = vlan.to_s

vlans = []
vlan.each_line do |net|
  vlans.push(net.chomp)
end

nw = choose do |menu|
  menu.index	= :number
  menu.index_suffix = ") "
  menu.flow = :columns_across
  
  menu.prompt = "Please select the proper VLAN: "
  vlans.each do |op|   
    menu.choices(op)
  end
end
nw = nw.chomp.to_s


cpu = choose do |menu|
  menu.index	= :number
  menu.index_suffix = ") "
  
  menu.prompt = "How many CPUs would you like? "
  
  menu.choices(2, 4, 6, 8)
end

mem = choose do |menu|
  menu.index	= :number
  menu.index_suffix = ") "
  
  menu.prompt = "How much memory would you like? "
  
  menu.choices(2048, 4096, 8192)
end

puts "Please wait while generating a list of templates to choose from ..."


# we generate a list of templates based off of the xenserver 
# pool we're connected to `chefvm current` in our bash prompt
# will display what pool you're connected to

template = `knife xenserver template list |grep Base | awk '{print $2}'`
template = template.to_s

templates = []
template.each_line do |line|
  templates.push(line.chomp)
end

tem = choose do |menu|
  menu.index	= :number
  menu.index_suffix = ") "
  
  menu.prompt = "Please select the template you would like to use: "
  templates.each do |op|   
    menu.choices(op)
  end
end

# We make it simple for the end user to select what datacenter role they're building in

cr1 = choose do |menu|
  menu.index	= :number
  menu.index_suffix = ") "
  
  menu.prompt = "What datacenter role would you like to apply? "
  
  menu.choices(:lvdefault, :dfdefault, :dubdefault, :londefault)
end

# Present the end user with a total list of roles to choose from

role = `knife role list`
role = role.to_s

roles = []
role.each_line do |role|
  roles.push(role.chomp)
end

cr2 = choose do |menu|
  menu.index	= :number
  menu.index_suffix = ") "
  menu.flow = :columns_across
  menu.list_option = 6 
  menu.prompt = "Please select the chef role: "
  roles.each do |op|   
    menu.choices(op)
  end
end

# We generate a list of chef environments to the end user 
# based off of the selection provided when they decided a role to use
# we use that to narrow down the chef environments
# Simple regex stuff to check the hostname of the VM being built

if hostname =~ /^(df|lv|dub|lon)dev/
  
  environment = `knife environment list |grep #{cr2} | grep -e dev$`
  environment = environment.to_s

  environments = []
  environment.each_line do |env|
    environments.push(env.chomp)
  end

  ce = choose do |menu|
    menu.index	= :number
    menu.index_suffix = ") "
    menu.flow = :columns_across
    menu.list_option = 6 
    menu.prompt = "Please select the chef environment: "
    environments.each do |op|   
      menu.choices(op)
    end
  end

elsif hostname =~ /^(df|lv|dub|lon)sb/
  
  environment = `knife environment list | grep #{cr2} | grep -e sbx$`
  environment = environment.to_s

  environments = []
  environment.each_line do |env|
    environments.push(env.chomp)
  end

  ce = choose do |menu|
    menu.index  = :number
    menu.index_suffix = ") "
    menu.flow = :columns_across
    menu.list_option = 6 
    menu.prompt = "Please select the chef environment: "
    environments.each do |op|   
      menu.choices(op)
    end
  end

else
  environment = `knife environment list |grep #{cr2} | grep -e prod$`
  environment = environment.to_s

  environments = []
  environment.each_line do |env|
    environments.push(env.chomp)
  end

  ce = choose do |menu|
    menu.index  = :number
    menu.index_suffix = ") "
    menu.flow = :columns_across
    menu.list_option = 6
    menu.prompt = "Please select the chef environment: "
    environments.each do |op|
      menu.choices(op)
    end
  end
end
   
    

count = ask("Please enter how many VMs you want: ") { |n| n.default ="1" }
count = count.to_i
count = count - 1

pw = ask("Enter the root password of the template: ") { |q| q.echo = "x" }


# create array of IPs expanded out from the count using IPAddr class built in to ruby to 
# validate the IP address and also to handle any roll over from x.x.x.255 
ips = [ip]
count.times do 
  ips << IPAddr.new(ips.last).succ.to_s
end

# increase the hostname by the count so that we can increment the proper hostnames
hosts = [hostname]
count.times do
  hosts << hostname.gsub(/\d+$/){|x|x.to_i+1}
  hostname = hosts.last
end

# smash the two arrays together to create a hash so that the hostname 
# and ip have a relationship. the zip method tells ruby that 
# there will be a 1 to 1 relationship with the values being smashed with it
pair = Hash[hosts.zip ips]

# for each relationships in the hash build out command and then 
# pass it to the system method. You can use your imagination on how this can translate
# to a knife command
pair.each do |h,i|
  if hostname =~ /^lv/
    tag = %{knife tag create #{h} upgrade-hq5}
    go = %{knife xenserver vm create --vm-name #{h} --vm-ip #{i} --vm-gateway #{gw} --vm-netmask #{nm} --vm-cpus #{cpu} --vm-memory #{mem} --vm-template #{tem} --environment #{ce} -N "#{nw}" -r \'role[#{cr1}],role[#{cr2}]\' -x root -P #{pw}}
    system(go)
    system(tag)
  else
    go = %{knife xenserver vm create --vm-name #{h} --vm-ip #{i} --vm-gateway #{gw} --vm-netmask #{nm} --vm-cpus #{cpu} --vm-memory #{mem} --vm-template #{tem} --environment #{ce} -N "#{nw}" -r \'role[#{cr1}],role[#{cr2}]\' -x root -P #{pw}}
    system(go)
  end
end

