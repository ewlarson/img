require 'iiif/presentation'
require 'nokogiri'
require 'open-uri'
require "down"
require "pathname"
require "json"

def extract_id(identifier)
  identifier.split('/').last
end

# Parse UIowa Islandora Object

## Doc

# @TODO: hardcoded; need to pass object identifier arg
# Hawkeye Highway
# parent_id = "ui:atlases_10618"
parent_id = "ui:testiadep_1760"

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

parent_metadata

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

children

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

  image = IIIF::Presentation::ImageResource.new()
  # Example
  # https://digital.lib.uiowa.edu/iiif/2/ui:atlases_10617~JP2~~default_public/full/2534,1626/0/default.jpg
  image['@id'] = "https://digital.lib.uiowa.edu/iiif/2/#{file_id}~JP2~~default_public/full/5000,/0/default.jpg"
  # image['@id'] = "http://images.exampl.com/loris2/my-image/full/#{canvas.width},#{canvas.height}/0/default.jpg"
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

puts manifest.to_json(pretty: true)
