# Haplo Platform                                     http://haplo.org
# (c) ONEIS Ltd 2006 - 2015                    http://www.oneis.co.uk
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.


# Provide utility functions to KWorkUnit JavaScript objects

module JSWorkUnitSupport

  def self.constructWorkUnit(workType)
    WorkUnit.new(:work_type => workType)
  end

  def self.loadWorkUnit(id)
    WorkUnit.find(id)
  end

  def self.executeQuery(query, firstResultOnly)
    units = build_ruby_query(query).order("created_at DESC,id DESC")
    if firstResultOnly
      first = units.first
      (first == nil) ? [] : [first]
    else
      units.to_a
    end
  end

  def self.executeCount(query)
    build_ruby_query(query).count()
  end

  def self.executeCountByTagsJSON(query, tags)
    tags = tags.to_a.compact
    if tags.empty?
      raise JavaScriptAPIError, "countByTags() requires at least one tag."
    end
    path_methods = COUNT_VALUE_METHODS[0..(tags.length-1)]
    last_method = path_methods.pop
    quoted_tags = tags.map { |tag| PGconn.quote(tag) }
    tag_values = quoted_tags.map { |qtag| "tags -> #{qtag}" } .join(', ')
    select = quoted_tags.each_with_index.map { |qtag, i| "tags -> #{qtag} as count_tag#{i}" } .join(', ')
    select << ", COUNT(*) as count_total"
    result = {}
    build_ruby_query(query).group(tag_values).order(tag_values).select(select).each do |wu|
      counts = result
      path_methods.each do |method|
        tag = wu.__send__(method) || ''
        counts = (counts[tag] ||= {})
      end
      last_tag = wu.__send__(last_method) || ''
      # Because NULL and "" are counted the same, add the total to any existing value, even though
      # the database will have done all the summing in the query for all the other values.
      counts[last_tag] = (counts[last_tag] || 0) + wu.count_total
    end
    return JSON.generate(result)
  end
  COUNT_VALUE_METHODS = [:count_tag0, :count_tag1, :count_tag2, :count_tag3]

  def self.build_ruby_query(query)
    # Build query, which must have at least one of work type and object reference
    work_type = query.getWorkType()
    obj_id = query.getObjId()
    unless work_type || obj_id
      raise JavaScriptAPIError, "Work unit queries must specify at least a work type or a ref"
    end
    units = work_type ? WorkUnit.where(:work_type => work_type) : nil
    units = (units ? units : WorkUnit).where(:obj_id => obj_id) if obj_id

    status = query.getStatus();
    if status == "open"
      units = units.where('closed_at IS NULL')
    elsif status == "closed"
      units = units.where('closed_at IS NOT NULL')
    elsif status != nil
      raise "logic error, bad status #{status}"  # should never run
    end

    visibility = query.getVisibility();
    if visibility == "visible"
      units = units.where('visible=TRUE')
    elsif visibility == "not-visible"
      units = units.where('visible=FALSE')
    elsif visibility != nil
      raise "logic error, bad visibility #{visibility}"  # should never run
    end

    created_by_id = query.getCreatedById()
    units = units.where(:created_by_id => created_by_id) if created_by_id != nil

    actionable_by_id = query.getActionableById()
    if actionable_by_id != nil
      user = User.cache[actionable_by_id]
      units = units.where("actionable_by_id IN (#{([user.id] + user.groups_ids).join(',')})")
    end

    closed_by_id = query.getClosedById()
    units = units.where(:closed_by_id => closed_by_id) if closed_by_id != nil

    tagValues = query.getTagValues()
    if tagValues != nil
      tagValues.each do |kv|
        units = units.where(WorkUnit::WHERE_TAG, kv.key, kv.value)
      end
    end

    units
  end

end

Java::ComOneisJsinterface::KWorkUnit.setRubyInterface(JSWorkUnitSupport)