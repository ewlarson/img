require 'iiif/presentation'
require 'nokogiri'
require 'open-uri'
require "down"
require "pathname"
require "json"

def img_scale(img_width)
  img_width > 5000 ? 5000 : img_width
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
#  "ui:atlases_3916",
# "ui:atlases_4881",
# "ui:atlases_7852",
# "ui:atlases_10618",
# "ui:sheetmaps_43",
# "ui:testiadep_977",
# "ui:testiadep_1517",
# "ui:testiadep_1760"

objects = [
  "ui:atlases_3916",
  "ui:atlases_4881",
  "ui:atlases_7852",
  "ui:atlases_10618",
  "ui:sheetmaps_43",
  "ui:testiadep_977",
  "ui:testiadep_1517",
  "ui:testiadep_1760"
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
  # Four paths here: 
  # 1. div.islandora-compound-thumb ex. https://digital.lib.uiowa.edu/islandora/object/ui:atlases_10518
  # 2. div.islandora-solr-content ex. https://digital.lib.uiowa.edu/islandora/object/ui:atlases_4881
  # 3. div.islandora-internet-archive-bookreader ex. https://digital.lib.uiowa.edu/islandora/object/ui:testiadep_1517
  # 4. div.islandora-large-image-content ex. https://digital.lib.uiowa.edu/islandora/object/ui%3Asheetmaps_43

  def extract_id(identifier)
    CGI.unescape(identifier.split('/').last)
  end

  ### Download Children info.json files
  def download_children_info_json_files(parent_id, children)
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
  end

  ### Recursively harvest children
  def recursively_harvest_children(children, page)
    page = Nokogiri::HTML(URI.open("https://digital.lib.uiowa.edu/" + page ))

    page.css("//dt.islandora-object-thumb/a").each do |child|
      id = extract_id(child.attributes["href"].value)
      children << { 
        title: child.attributes["title"].value, 
        id: id,
        info: "https://digital.lib.uiowa.edu/iiif/2/#{id}~JP2~~default_public/info.json"
      }
    end

    # Recursively harvest children
    if page.css("//li.pager-next/a").size > 0
      next_page = page.css("//li.pager-next/a").first.attributes["href"].value
      recursively_harvest_children(children, next_page)
    end

    children
  end

  children = []

  def harvest_path(doc)
    if doc.css("//div.islandora-compound-thumb/a").size > 0
      "compound"
    elsif doc.css("//div.islandora-solr-content").size > 0
      "solr"
    elsif doc.css("//div.islandora-internet-archive-bookreader").size > 0
      "bookreader"
    elsif doc.css("//div.islandora-large-image-content").size > 0
      "solo"
    else
      puts "Cannot deterine path"
    end
  end

  path = harvest_path(doc)
  puts "Path: #{path}"

  if path == "compound"
    doc.css("//div.islandora-compound-thumb/a").each do |child|
      id = extract_id(child.attributes["href"].value)
      children << { 
        title: child.attributes["title"].value, 
        id: id,
        info: "https://digital.lib.uiowa.edu/iiif/2/#{id}~JP2~~default_public/info.json"
      }
    end

    download_children_info_json_files(parent_id, children)

  elsif path == "solr"
    doc.css("//dt.solr-grid-thumb/a").each do |child|
      child_page = Nokogiri::HTML(URI.open("https://digital.lib.uiowa.edu" + child.attributes["href"]))
      child_page.css("//div.islandora-compound-thumb/a").each do |child|
        id = extract_id(child.attributes["href"].value)
        children << { 
          title: child.attributes["title"].value, 
          id: id,
          info: "https://digital.lib.uiowa.edu/iiif/2/#{id}~JP2~~default_public/info.json"
        }
      end
    end

    download_children_info_json_files(parent_id, children)
    
  elsif path == "bookreader"
    page = Nokogiri::HTML(URI.open("https://digital.lib.uiowa.edu/islandora/object/" + parent_id + "/pages"))

    page.css("//dt.islandora-object-thumb/a").each do |child|
      id = extract_id(child.attributes["href"].value)
      children << { 
        title: child.attributes["title"].value, 
        id: id,
        info: "https://digital.lib.uiowa.edu/iiif/2/#{id}~JP2~~default_public/info.json"
      }
    end

    # Recursively harvest children
    if page.css("//li.pager-next/a")
      next_page = page.css("//li.pager-next/a").first.attributes["href"].value
      children = recursively_harvest_children(children, next_page)
    end

    # Download Children info.json files
    download_children_info_json_files(parent_id, children)
  
  elsif path == "solo"
    children << { 
      title: parent_metadata["Title"],
      id: parent_id,
      info: "https://digital.lib.uiowa.edu/iiif/2/#{parent_id}~JP2~~default_public/info.json"
    }

    download_children_info_json_files(parent_id, children)
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

  # Iterate over Children Files > Add Canvas with Image for each File
  children.each do |child|
    file_contents = JSON.parse(File.read("#{parent_id}/#{child[:id]}/info.json"))

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
    canvas.label = children.detect {|c| c[:id] == child[:id] }[:title]

    service = IIIF::Presentation::Resource.new('@context' => 'http://iiif.io/api/image/2/context.json', 'profile' => 'http://iiif.io/api/image/2/level2.json', '@id' => file_contents["@id"])

    # Image 
    image = IIIF::Presentation::ImageResource.new()
    
    # Example
    # https://digital.lib.uiowa.edu/iiif/2/ui:atlases_10617~JP2~~default_public/full/2534,1626/0/default.jpg
    # image['@id'] = "http://images.exampl.com/loris2/my-image/full/#{canvas.width},#{canvas.height}/0/default.jpg"
    
    image['@id'] = "https://digital.lib.uiowa.edu/iiif/2/#{child[:id]}~JP2~~default_public/full/#{img_scale(canvas.width)},/0/default.jpg"
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