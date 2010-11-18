#!/usr/bin/ruby1.8 -w
# -*- coding: utf-8 -*-
#
# Copyright:: Copyright 2010 Sensebloom Lda.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Implementation of the geomodel library for dm-appengine.

require 'appengine-apis/datastore'
require 'dm-core'

module GeoModel
  GeoPt = AppEngine::Datastore::GeoPt

  #Alphabet length must always be GridSize**2
  GridSize = 4
  Alphabet = '0123456789abcdef'
  #At 13 characters resolution, the cell can be considered a single point.
  MaxResolution = 7
  #List of cell dimensions in degrees for each resolution, the format for
  #each span is [lat, lng]. The index for each span is the same as the
  #length of the corresponding geohash ;)
  CellSizes = (1..MaxResolution).map do |res|
    num_cells = GridSize**res
    lng = 360.0 / num_cells
    lat = 180.0 / num_cells
    [lat, lng]
  end

  North = 90.0
  South = -90.0
  East = 180.0
  West = -180.0

  #Add location properties to data model
  def self.included cls
    cls.extend(ClassMethods)
    cls.property :location, GeoPt, :required => true
    cls.property :geocells, DataMapper::Property::List
    cls.before :save do |thing|
      thing.update_geocells
    end
  end

  #Update model's geocells based on current location
  def update_geocells
    self.geocells = (1..MaxResolution).map do |res|
      GeoModel.compute(location, res).hex
    end
  end

  #Returns a new GeoPt for the given "lat,lng" string
  def geoPtFromString(str)
    lat, lng = str.split(",")
    GeoPt.new(lat.to_f, lng.to_f)
  end

  module ClassMethods
    #Does a bounding box datastore query, returns a Datamapper::Collection
    def within(sw, ne)
      res = GeoModel.best_query_res(sw, ne)
      sw_cell = GeoModel.compute(sw)[0...res]
      ne_cell = GeoModel.compute(ne)[0...res]
      cells = GeoModel.query_cells(sw_cell, ne_cell)
      puts "GeoModel.within: Bounds query, resolution = #{res}. Going to query #{cells.length} geocells"
      self.all(:geocells => cells)
    end
  end

  ######################################################################
  # Support methods below, nothing interesting here unless there are
  # bugs... :P
  ######################################################################

  #Return the best(lol) query resolution (geohash string length)
  #for the given bounding box.
  def self.best_query_res(sw, ne)
    #We are going to choose a cell size that is right above the
    #smallest of the 2 spans. Is this ok?
    #TODO (tony): Do some measurements and performance tweaks.
    span = [ne.latitude - sw.latitude,
            ne.longitude - sw.longitude].min
    CellSizes.inject(0) { |res, i| i[0] > span ? res + 1 : res }
  end

  #Returns the cells necessary for a query to the given bounds
  def self.query_cells(sw_cell, ne_cell)
    res = sw_cell.length
    return nil if res != ne_cell.length
    sw_idx = cell_to_idx(sw_cell)
    ne_idx = cell_to_idx(ne_cell)

    if ne_idx[0] < sw_idx[0] || ne_idx[1] < sw_idx[1]
      #Abort if NE coordinate is smaller... #TODO/FIXME: Take care of
      #180/-180º meridian ;)
      cells = nil
    elsif (ne_idx[0] == ne_idx[1] && ne_idx[1] && sw_idx[0] &&
           sw_idx[0] == sw_idx[1] && sw_idx[1] == 0)
      #If all cells are 0, map is very very zoomed out, just return
      #the top-level cells.
      cells = Alphabet.split("").map { |c| c.hex }
    else
      #Do calculation of necessary cells for the query
      cells = []
      (sw_idx[0]..ne_idx[0]).step(GridSize**(MaxResolution-res)) do |x|
        (sw_idx[1]..ne_idx[1]).step(GridSize**(MaxResolution-res)) do |y|
          cells << idx_to_cell([x,y]).hex
        end
      end
    end
    cells
  end

  #Calculates the cell containing the given point.
  def self.compute(pt, res = MaxResolution)
    lat, lng = pt.latitude, pt.longitude
    north = North
    south = South
    east = East
    west = West

    cell = ''
    while cell.length < res
      lat_span = (north-south) / GridSize
      lng_span = (east-west) / GridSize

      x = [(GridSize * (lng - west) / (east - west)).to_i, GridSize-1].min
      y = [(GridSize * (lat - south) / (north - south)).to_i, GridSize-1].min
      cell << get_char([x,y])

      south += lat_span * y
      north = south + lat_span
      west += lng_span * x
      east = west + lng_span
    end
    cell
  end

  #Returns the alphabet character at the given position
  def self.get_char(pos)
    Alphabet[(pos[1] & 2) << 2 |
             (pos[0] & 2) << 1 |
             (pos[1] & 1) << 1 |
             (pos[0] & 1) << 0]
  end

  #Returns the index for the given char in the 4x4 table
  def self.get_pos(chr)
    idx = Alphabet.index(chr)
    [(idx & 4) >> 1 | (idx & 1) >> 0,
     (idx & 8) >> 2 | (idx & 2) >> 1]
  end

  #Returns the numeric index for the cell in [x,y] format
  def self.cell_to_idx(cell)
    idx = [0, 0]
    cell.split("").each_with_index do |chr, i|
      pos = get_pos(chr)
      mult = (GridSize ** (MaxResolution - (i+1)))
      idx[0] += pos[0] * mult
      idx[1] += pos[1] * mult
    end
    idx
  end

  #Returns the cell for the given index and resolution
  def self.idx_to_cell(idx)
    cell = ''
    i=0
    while idx[0] > 0 || idx[1] > 0 do
      divider = (GridSize ** (MaxResolution - (i+1)))
      pos = [idx[0] / divider, idx[1] / divider]
      cell << get_char(pos)
      idx[0] = idx[0] % divider
      idx[1] = idx[1] % divider
      i += 1
    end
    cell
  end
end
