##
# This file is part of WhatWeb and may be subject to
# redistribution and commercial restrictions. Please see the WhatWeb
# web site for more information on licensing and terms of use.
# https://morningstarsecurity.com/research/whatweb
##
Plugin.define do
  name "Ubiquiti-UniFi"
  authors [
    "John de Kroon <john.de.kroon@cyberant.com>", # 2025-10-18
  ]
  version "0.1"
  description "Detection of Ubiquiti UniFi Network controllers / UniFi OS"
  website "https://ui.com/"

  # Dorks #
  dorks [
    'intitle:"UniFi Network"'
  ]

  # Matches #
  matches [
    {
      :text => "<div id=\"unifi-network-app-container\"></div>"
    },
    {
      :text => "<title>UniFi Network</title>"
    },
    {
      :text => "<title>UniFi OS</title>"
    },
    {
      :model => /UNIFI_OS_MANIFEST[\s\S]{0,400}?"shortName"\s*:\s*"([^"]+)"/
    },
    # /assets/images/1024.png?udm-3.0.0  — first token is the model slug, second is the version
    {
      :version => /\/assets\/images\/1024\.png\?[a-z0-9]+-([0-9]+\.[0-9]+\.[0-9]+)/i
    },

    # Detect the public status page to extract the version
    {
      :url      => "/status",
      :search   => "body",
      :version => /"server_version"\s*:\s*"([^"]+)"/,
    }
  ]
end
