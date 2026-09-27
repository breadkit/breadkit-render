# frozen_string_literal: true

module Breadkit
  module Render
    class OrthogonalRouter
      DIRECTIONS = [[1, 0], [0, 1], [-1, 0], [0, -1]].freeze

      def initialize(obstacles)
        @obstacles = obstacles.map { |left, bottom, right, top| [left - 0.35, bottom - 0.35, right + 0.35, top + 0.35] }
        @used_edges = Hash.new(0)
      end

      def route(from, to)
        start = breakout(from, to)
        goal = breakout(to, from)
        start_grid, goal_grid = [start, goal].map { |point| point.map { |coordinate| (coordinate * 2).round } }
        grid = search(start_grid, goal_grid)
        points = [from, start, [start[0], start_grid[1] / 2.0]] + grid.map { |x, y| [x / 2.0, y / 2.0] } +
                 [[goal[0], goal_grid[1] / 2.0], goal, to]
        simplify(points)
      end

      private

      def breakout(point, target)
        box = @obstacles.find { |left, bottom, right, top| point[0].between?(left, right) && point[1].between?(bottom, top) }
        return point unless box

        left = (box[0] * 2).floor / 2.0 - 0.5
        right = (box[2] * 2).ceil / 2.0 + 0.5
        distance_left, distance_right = point[0] - left, right - point[0]
        x = if distance_left == distance_right
          target[0] < point[0] ? left : right
        else
          distance_left < distance_right ? left : right
        end
        [x, point[1]]
      end

      def search(start, goal)
        all_x = [start[0], goal[0]] + @obstacles.flat_map { |box| [box[0] * 2, box[2] * 2] }
        all_y = [start[1], goal[1]] + @obstacles.flat_map { |box| [box[1] * 2, box[3] * 2] }
        xmin, xmax = all_x.min.floor - 4, all_x.max.ceil + 4
        ymin, ymax = all_y.min.floor - 4, all_y.max.ceil + 4
        heap = []
        serial = 0
        initial = [start[0], start[1], -1]
        distance = { initial => 0 }
        parent = {}
        push(heap, [heuristic(start, goal), 0, serial, *initial])
        until heap.empty?
          _score, cost, _serial, x, y, direction = pop(heap)
          key = [x, y, direction]
          next unless distance[key] == cost
          if [x, y] == goal
            path = [key]
            path << parent[path.last] while parent.key?(path.last)
            points = path.reverse.map { |item| item.first(2) }
            points.each_cons(2) { |a, b| @used_edges[edge(a, b)] += 1 }
            return points
          end
          DIRECTIONS.each_with_index do |(dx, dy), next_direction|
            nx, ny = x + dx, y + dy
            next unless nx.between?(xmin, xmax) && ny.between?(ymin, ymax)
            next if blocked?(nx, ny) && [nx, ny] != goal

            next_key = [nx, ny, next_direction]
            step = 1 + (direction >= 0 && direction != next_direction ? 2 : 0) + @used_edges[edge([x, y], [nx, ny])] * 5
            next_cost = cost + step
            next if distance.key?(next_key) && distance[next_key] <= next_cost

            distance[next_key] = next_cost
            parent[next_key] = key
            serial += 1
            push(heap, [next_cost + heuristic([nx, ny], goal), next_cost, serial, *next_key])
          end
          raise Error, "automatic wire route exceeds search limit" if distance.length > 100_000
        end
        raise Error, "no obstacle-free wire route found"
      end

      def blocked?(x, y)
        @obstacles.any? { |left, bottom, right, top| x / 2.0 > left && x / 2.0 < right && y / 2.0 > bottom && y / 2.0 < top }
      end

      def heuristic(point, goal)
        (point[0] - goal[0]).abs + (point[1] - goal[1]).abs
      end

      def edge(a, b)
        (a <=> b).negative? ? [a, b] : [b, a]
      end

      def simplify(points)
        result = []
        points.each do |point|
          next if result.last == point
          result.pop if result.length >= 2 &&
                        (result[-2][0] == result[-1][0] && result[-1][0] == point[0] ||
                         result[-2][1] == result[-1][1] && result[-1][1] == point[1])
          result << point
        end
        result
      end

      def push(heap, item)
        index = heap.length
        heap << item
        while index.positive?
          parent = (index - 1) / 2
          break if (heap[parent] <=> item) <= 0

          heap[index] = heap[parent]
          index = parent
        end
        heap[index] = item
      end

      def pop(heap)
        first = heap.first
        last = heap.pop
        return first if heap.empty?

        index = 0
        while (child = index * 2 + 1) < heap.length
          child += 1 if child + 1 < heap.length && (heap[child + 1] <=> heap[child]).negative?
          break if (last <=> heap[child]) <= 0

          heap[index] = heap[child]
          index = child
        end
        heap[index] = last
        first
      end
    end
  end
end
