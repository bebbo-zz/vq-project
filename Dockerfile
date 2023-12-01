FROM alpine:latest

COPY app.rb ffmpeg ffprobe  .
COPY vmaf_v0.6.1.json /vmaf/model/ 
RUN apk add --no-cache aws-cli
RUN apk add --no-cache ruby 
RUN gem install opensearch-ruby