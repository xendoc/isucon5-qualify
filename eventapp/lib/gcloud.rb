require 'json'

module Isucon5Portal::GCloud
  def self.valid_server_info(project_id, zone_name, instance_name)
    info = server_info(project_id, zone_name, instance_name)
    return nil unless info
    return nil if check_server_info(info).size() > 0
    info
  end

  def self.valid_ip_address(project_id, zone_name, instance_name)
    ip_address(valid_server_info(project_id, zone_name, instance_name))
  end

  def self.server_info(project_id, zone_name, instance_name)
    jsonText = IO.popen("gcloud compute --project #{project_id} instances list --zones #{zone_name} --format json") do |io|
      io.read()
    end
    serverInfoList = JSON.parse(jsonText) rescue nil
    return nil unless serverInfoList
    serverInfoList.select{|obj| obj["name"] == instance_name}.first
  end

  def self.check_server_info(info)
    cautions = []
    unless info["machineType"] == "n1-highcpu-4"
      cautions << "マシンタイプは n1-highcpu-4 を選択してください"
    end
    if info["disks"].any?{|d| d["type"] != "PERSISTENT"}
      cautions << "ディスクタイプは PERSISTENT を選択してください"
    end
    unless ip_address(info)
      cautions << "EXTERNAL IPアドレスが確認できません"
    end
    cautions
  end

  def self.ip_address(info)
    return nil unless info
    valid_iface = info["networkInterfaces"].select{|iface| iface["accessConfigs"].any?{|c| c["natIP"] } }
    return nil if valid_iface.empty?
    valid_iface.first["accessConfigs"].select{|c| c["natIP"] }.first["natIP"]
  end

  def example
    {
      "canIpForward"=>false,
      "cpuPlatform"=>"Intel Ivy Bridge",
      "creationTimestamp"=>"2015-09-23T22:45:14.458-07:00",
      "disks"=>[
        {
          "boot"=>true,
          "deviceName"=>"base1",
          "index"=>0,
          "interface"=>"SCSI",
          "kind"=>"compute#attachedDisk",
          "licenses"=>["https://www.googleapis.com/compute/v1/projects/ubuntu-os-cloud/global/licenses/ubuntu-1504-vivid"],
          "mode"=>"READ_WRITE",
          "source"=>"najeira",
          "type"=>"PERSISTENT"
        }
      ],
      "id"=>"10342501450497407499",
      "kind"=>"compute#instance",
      "machineType"=>"n1-highcpu-4",
      "metadata"=>{
        "fingerprint"=>"bBkb9akTNGc=",
        "items"=>[
          { "key"=>"sshKeys",
            "value"=>"root:ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDAqV5m5JPu2/FPJ77JhBUP9xNtEV3pSTj+HIw5DSQ80Y/LhCu7ewGZSBB71FoVR6Sty6F+QIWgvR61PO1SJDY9a6kNRMnnZ0LS28pdYuUtSIaXg+GrMpRc1ZgXPm5fAyQq7A4R9dqAONlDvz4eGy2c6rIO4uLJ1g8tjq54mR7JsP9HO5VjZkavtq/oLFfzimVCIm/Do9NbIn4rewOzg51ggdmXA0kw2HFnFBE9mjUAyfN76FIbCuXOnE6q4fqoVcOz8FngTigokZSpEvwRFWmdJ6WN8Zakn9q2npb7Zypwzz6PoGbNWWkRtj/Z4TYafNdyZO0WxHZ7DMg/CYBZ9GgZ root@base-image.isucon.net"}
        ],
        "kind"=>"compute#metadata"
      },
      "name"=>"najeira",
      "networkInterfaces"=>[
        {
          "accessConfigs"=> [
            { "kind"=>"compute#accessConfig",
              "name"=>"external-nat",
              "natIP"=>"107.167.187.73",
              "type"=>"ONE_TO_ONE_NAT"}
          ],
          "name"=>"nic0",
          "network"=>"default",
          "networkIP"=>"10.240.0.5"
        }
      ],
      "scheduling"=>{"automaticRestart"=>false, "onHostMaintenance"=>"TERMINATE", "preemptible"=>false},
      "selfLink"=>"https://www.googleapis.com/compute/v1/projects/isucon5-qualify/zones/asia-east1-b/instances/najeira",
      "serviceAccounts"=>[
        { "email"=>"133268897613-compute@developer.gserviceaccount.com",
          "scopes"=>[
            "https://www.googleapis.com/auth/devstorage.read_write",
            "https://www.googleapis.com/auth/logging.write"
          ]
        }],
      "status"=>"RUNNING",
      "tags"=>{"fingerprint"=>"FYLDgkTKlA4=", "items"=>["http-server"]},
      "zone"=>"asia-east1-b"
    }
  end
end
