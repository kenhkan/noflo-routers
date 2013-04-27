noflo = require("noflo")
_ = require("underscore")
_s = require("underscore.string")

class GroupRouter extends noflo.Component

  description: _s.clean "routes IPs based on groups, which are matched and
    routed but not removed when forwarding"

  constructor: ->
    @routes = []

    @inPorts =
      in: new noflo.Port
      routes: new noflo.Port
      reset: new noflo.Port
    @outPorts =
      out: new noflo.ArrayPort
      routes: new noflo.Port
      missed: new noflo.Port

    @inPorts.reset.on "disconnect", =>
      @routes = []

    @inPorts.routes.on "data", (segments) =>
      if _.isArray(segments)
        @routes.push _.map segments, (segment) -> new RegExp(segment)
      else
        throw new Error
          message: "Route must be array of segments"
          source: segments

    @inPorts.in.on "connect", =>
      # Where we are in terms of groups and whether they match
      @breadcrumb = []

    @inPorts.in.on "begingroup", (group) =>
      @breadcrumb.push(group)
      @matchRoute(group, true)

      if @matchedIndexes.length > 0
        for index in @matchedIndexes
          @outPorts.out.beginGroup(group, index)
      else if @outPorts.missed.isAttached()
        @outPorts.missed.beginGroup(group)

    @inPorts.in.on "data", (data) =>
      if @matchedIndexes.length > 0
        for index in @matchedIndexes
          @outPorts.out.send(data, index)
      else if @outPorts.missed.isAttached()
        @outPorts.missed.send(data)

    @inPorts.in.on "endgroup", (group) =>
      @breadcrumb.pop()
      @matchRoute(group, false)

      if @matchedIndexes.length > 0
        for index in @matchedIndexes
          @outPorts.out.endGroup(index)
      else if @outPorts.missed.isAttached()
        @outPorts.missed.endGroup()

    @inPorts.in.on "disconnect", =>
      if @outPorts.routes.isAttached()
        for index in @matchedIndexes
          @outPorts.routes.send(@routes[index])
        @outPorts.routes.disconnect()

      @outPorts.out.disconnect()
      @outPorts.missed.disconnect()

  # Re-evaluate whether there is a route match. Pass a boolean as the
  # second parameter to indicate whether it's beginning a new group.
  matchRoute: (group, toBegin) ->
    # The routes that currently match. Start with all matching
    @matchedIndexes = _.map @routes, (routes, index) -> index

    for group, step in @breadcrumb
      indexesToRemove = []

      for index in @matchedIndexes
        route = @routes[index]

        if route[step]? and not group.match(route[step])?
          indexesToRemove.push(index)

      for index in indexesToRemove
        @matchedIndexes.splice(@matchedIndexes.indexOf(index), 1)

exports.getComponent = -> new GroupRouter
