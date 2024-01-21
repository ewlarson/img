require 'iiif/presentation'
require 'nokogiri'
require 'open-uri'
require "down"
require "pathname"
require "json"

def img_scale(img_width)
  if img_width > 5000
    5000
  else
    img_width
  end
end

def extract_id(identifier)
  identifier.split('/').last
end

def write_line(obj_id)
  "<li>
    #{obj_id}: 
    <a href=\"/img/#{obj_id}/manifest.json\">Manifest</a>
    |
    <a href=\"/img/#{obj_id}/index.html\">Index</a>
  </li>
  "
end

# Parse UIowa Islandora Object
## Objects to Harvest


# @TODO - "ui:atlases_7852" / class="solr-grid-field"
# @TODO - "ui:atlases_4881" / class="solr-grid-field"

objects = [
  "ui:atlases_10618",
  "ui:testiadep_1760",
  "ui:testiadep_977",

]

objects.each do |obj|
  parent_id = obj

  puts "Parsing - HTML for #{obj}"
  doc = Nokogiri::HTML(URI.open("https://digital.lib.uiowa.edu/islandora/object/#{parent_id}"))

  ### Parent Metadata
  elements = []
  doc.css("//dl.islandora-inline-metadata").first.children.each_with_index do |child, index|
    if index.odd?
      elements << child.text.strip
    end
  end

  parent_metadata = {}
  elements.each_slice(2) do | key, value |
    parent_metadata[key] = value
  end

  puts parent_metadata

  ### Children
  def extract_id(identifier)
    CGI.unescape(identifier.split('/').last)
  end

  children = []
  doc.css("//div.islandora-compound-thumb/a").each do |child|
    id = extract_id(child.attributes["href"].value)
    children << { 
      title: child.attributes["title"].value, 
      id: id,
      info: "https://digital.lib.uiowa.edu/iiif/2/#{id}~JP2~~default_public/info.json"
    }
  end

  ### Download Children info.json files

  children.each_with_index do |child, index|
    if FileTest.exist?("./#{parent_id}/#{child[:id]}/info.json")
      puts "Exists - #{child[:info]}"
    else
      puts "Downloading - #{child[:info]}"
      sleep(1)
      tempfile = Down.download(child[:info])
      FileUtils.mkdir_p("./#{parent_id}/#{child[:id]}")
      FileUtils.mv(tempfile.path, "./#{parent_id}/#{child[:id]}/info.json")
    end
  end

  ### Generate Manifest
  seed = {
      '@id' => "https://ewlarson.github.io/img/#{parent_id}/manifest.json",
      'label' => parent_metadata["Title"],
      'metadata' => parent_metadata.collect{ |key, value| {label: key, value: value }}
  }
  # Any options you add are added to the object
  manifest = IIIF::Presentation::Manifest.new(seed)

  # sequences array is generated for you, but let's add a sequence object
  sequence = IIIF::Presentation::Sequence.new()
  sequence['@id'] = "https://ewlarson.github.io/img/#{parent_id}/manifest.json#sequence-1"
  sequence['label'] = 'Current order'
  sequence['viewingDirection'] = 'left-to-right'
  manifest.sequences << sequence

  # Iterate over Files > Add Canvas with Image for each File
  Dir.glob("#{parent_id}/**").each do |dir|
    next if dir == "#{parent_id}/manifest.json"
    next if dir == "#{parent_id}/index.html"

    file_id = dir.split("/").last
    file_contents = JSON.parse(File.read(dir + "/info.json"))

    canvas = IIIF::Presentation::Canvas.new()

    # All classes act like `ActiveSupport::OrderedHash`es, for the most part.
    # Use `[]=` to set JSON-LD properties...
    canvas['@id'] = file_contents["@id"]
    # ...but there are also accessors and mutators for the properties mentioned in 
    # the spec

    # @TODO - Sanity check these
    # Can return Error: "The requested pixel area exceeds the maximum threshold set in the configuration."
    canvas.width = file_contents["width"]
    canvas.height = file_contents["height"]
    canvas.label = children.detect {|c| c[:id] == file_id }[:title]

    service = IIIF::Presentation::Resource.new('@context' => 'http://iiif.io/api/image/2/context.json', 'profile' => 'http://iiif.io/api/image/2/level2.json', '@id' => file_contents["@id"])

    # Image 
    image = IIIF::Presentation::ImageResource.new()
    
    # Example
    # https://digital.lib.uiowa.edu/iiif/2/ui:atlases_10617~JP2~~default_public/full/2534,1626/0/default.jpg
    # image['@id'] = "http://images.exampl.com/loris2/my-image/full/#{canvas.width},#{canvas.height}/0/default.jpg"
    
    image['@id'] = "https://digital.lib.uiowa.edu/iiif/2/#{file_id}~JP2~~default_public/full/#{img_scale(canvas.width)},/0/default.jpg"
    image.format = "image/jpeg"
    image.width = canvas.width
    image.height = canvas.height
    image.service = service

    images = IIIF::Presentation::Resource.new(
      '@type' => 'oa:Annotation', 
      'motivation' => 'sc:painting', 
      '@id' => "#{canvas['@id']}/images", 
      'resource' => image,
      'on' => file_contents["@id"]
    )

    canvas.images << images

    # Add other content resources
    # oc = IIIF::Presentation::Resource.new('@id' => 'http://example.com/content')
    # canvas.other_content << oc

    manifest.sequences.first.canvases << canvas
  end

  # Write Manifest
  puts "Writing - manifest.json for #{obj}"
  File.write("./#{parent_id}/manifest.json", manifest.to_json(pretty: true))

  # Write Clover IIIF Viewer
  clover_html = "
  <html>
    <head>
      <title>Clover IIIF - Web Component</title>
      <meta charset=\"UTF-8\" />
    </head>
    <body>
      <script src=\"https://www.unpkg.com/@samvera/clover-iiif@latest/dist/web-components/index.umd.js\"></script>
  
      <clover-viewer
        id=\"https://ewlarson.github.io/img/#{parent_id}/manifest.json\"
      />
    </body>
  </html>
  "

  puts "Writing - index.html for #{obj}"
  File.write("./#{parent_id}/index.html", clover_html)
  # puts manifest.to_json(pretty: true)
end

puts "Writing - project index.html"

homepage_html = "
<html>
  <head>
    <title>Clover IIIF - Web Component</title>
    <meta charset=\"UTF-8\" />
  </head>
  <body>
    <ul>
"
objects.each do |obj|
  homepage_html += write_line(obj)
end
   
homepage_html += "
    </ul>
  </body>
</html>
"
File.write("index.html", homepage_html)