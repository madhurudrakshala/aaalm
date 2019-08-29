# TODO check for ALL_IPs
@load base/utils/directions-and-hosts
@load base/utils/site

@load policy/protocols/conn/mac-logging
@load policy/protocols/conn/vlan-logging

@load ether_ipv4

module EtherIPv4;

event zeek_init() {
    Log::create_stream(EtherIPv4::LOG_DEV, [$columns=EtherIPv4::TrackedIP, $path="device"]);
    Log::create_stream(EtherIPv4::LOG_NET, [$columns=EtherIPv4::TrackedSubnet, $path="subnet"]);
}

#redef use_public = T;

event zeek_done() {
    local vlan_subnets = build_vlans(vlan_ip_emitted, F);
    local router_subnets = find_routers(F);

    local subnet_vlan: table[subnet] of set[count];

    for (vlan in vlan_subnets) {
        local tracked_snet_vlan = vlan_subnets[vlan];


        local sn = tracked_snet_vlan$net;
        local t: set[count] = set();

        if (sn !in subnet_vlan) {
            subnet_vlan[sn] = t;
        } else {
            t = subnet_vlan[sn];
        }
        add t[vlan];

        if (sn in router_subnets) {
            local mac = router_subnets[sn];
            tracked_snet_vlan$router_mac = mac;
        }

        Log::write(LOG_NET, tracked_snet_vlan);
    }

    #print "RS", router_subnets;
    # TODO include router subnets in output

    #print "VS", vlan_subnets;
    print "SV", subnet_vlan;
    #output_summary();

    for (_ip in all_src_ips) {
        local pd = all_src_ips[_ip];

        if (!use_public && !Site::is_private_addr(_ip)) {
            next;
        }

        for (mac in pd$seen_macs) {
            # TODO sort by order and pick the first; count different macs
            pd$inferred_mac = mac;
        }

        local vs: vector of subnet = matching_subnets(_ip/32, subnet_vlan);

        local poss_vlan_subnet: subnet = 255.255.255.255/32;
        local poss_vlan: count = 0;


        print _ip, vs;
        for (i in vs) {
            poss_vlan_subnet = vs[i];
            #poss_vlan = subnet_vlan[vs[i]];
        }

        local rs: vector of subnet = matching_subnets(_ip/32, router_subnets);

        local poss_router_mac = "";
        local poss_router_subnet: subnet = 255.255.255.255/32;
        for (i in rs) {
            poss_router_subnet = rs[i];
            #poss_router_mac = router_subnets[rs[i]];
        }

        # TODO assign correct type
        pd$device_type = DEVICE;
        pd$possible_vlan = poss_vlan;

        # TODO decide which is more specific and assign based on that
        pd$possible_subnet = poss_vlan_subnet;
        pd$possible_r_subnet = poss_router_subnet;

        Log::write(LOG_DEV, pd);
    }
}