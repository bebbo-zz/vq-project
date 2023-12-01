require 'json'
require 'opensearch'

org_file = ENV["ORG_FILE"]
dis_file = ENV["DIS_FILE"]
res = ENV["RES_VALUE"]
index = ENV['INDEX']
@start_time_milli = ENV["START_TIME"]

def execute_quality_cal(org_file, dis_file, res, index)
  puts "Execute Quality calc!!!"
  org_file_name = org_file.split("/").last
  dis_file_name = dis_file.split("/").last
  puts "Downloading the org file... #{org_file}"
  `aws s3 cp #{org_file} #{org_file_name} `
  puts "Downloading the dis file...#{dis_file}"
  `aws s3 cp #{dis_file} #{dis_file_name}`
  width = get_width(dis_file_name)
  height = get_height(dis_file_name)
  res = "#{width}x#{height}"
  `./ffmpeg -i #{dis_file_name} -i #{org_file_name}  -lavfi "[0:v]setpts=PTS-STARTPTS[reference];[1:v]scale=#{res}:flags=bicubic,setpts=PTS-STARTPTS[distorted]; [distorted][reference]libvmaf=log_fmt=JSON:log_path=/tmp/frame_info.json:model=path=/vmaf/model/vmaf_v0.6.1.json:n_threads=4:feature=name=psnr|name=float_ssim|name=float_ms_ssim" -f null -`
  num_frames = get_num_frames(org_file_name)
  file = File.read('/tmp/frame_info.json')
  data_hash = JSON.parse(file)
  populate_vq(data_hash, index, num_frames, width, height )
end

def get_num_frames(org_file_name)
  num_frames = `./ffprobe -count_frames -v error -select_streams v:0 -show_entries stream=nb_read_frames -of default=nokey=1:noprint_wrappers=1 #{org_file_name}`
  num_frames = num_frames.split("\n").last
  num_frames
end

def get_width(dis_file_name)
  width = `./ffprobe -count_frames -v error -select_streams v:0 -show_entries stream=width -of default=nokey=1:noprint_wrappers=1 #{dis_file_name}`
  width = width.split("\n").last
  width
end

def get_height(dis_file_name)
  height = `./ffprobe -count_frames -v error -select_streams v:0 -show_entries stream=height -of default=nokey=1:noprint_wrappers=1 #{dis_file_name}`
  height = height.split("\n").last
  height
end

def get_frame_rate(dis_file_name)
  fps = `./ffprobe -count_frames -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=nokey=1:noprint_wrappers=1 #{dis_file_name}`
  fps = fps.split("\n").last
  fps_a = fps.split("/")
  fps = fps_a[0] / fps_a[1]
  fps
end

def populate_vq(data_hash, index, num_frames, width, height)
  ops_host = ENV['OPS_HOST']
  ops_user = ENV['OPS_USER']
  ops_password = ENV['OPS_PASSWORD']
  client = OpenSearch::Client.new(
    host: ops_host,
    user: ops_user,
    password: ops_password,
    transport_options: { ssl: { verify: false } }  # For testing only. Use certificate for validation.
  )  

  index = index.to_i - 1
  start_index = index.to_i * num_frames.to_i
  data_hash["frames"].each do |frameinfo|
    puts "Frameinfo => #{frameinfo}"
    puts "Index Frame => #{start_index}"
    body = {
      "frame_no": start_index,
      "vmaf_score": frameinfo["metrics"]["vmaf"],
      "psnr_y": frameinfo["metrics"]["psnr_y"],
      "psnr_cb": frameinfo["metrics"]["psnr_cb"],
      "psnr_cr": frameinfo["metrics"]["psnr_cr"],
      "ssim": frameinfo["metrics"]['float_ssim'],
      "ms_ssim": frameinfo["metrics"]['float_ms_ssim'],
      "width": width,
      "height": height
    }
    response = client.index(
      index: "vq-index",
      body: body,
      id: "#{ENV["ORG_FILE"]}##{start_index}",
      refresh: true
    )
    puts response
    start_index = start_index + 1
  end
end

puts "org file => #{org_file}"
puts "Dis File => #{dis_file}"
puts "Resolution => #{res}"
puts "Index => #{index}"
execute_quality_cal(org_file, dis_file, res, index)