# frozen_string_literal: true

module OnlineMigrations
  # @private
  class BatchIterator
    attr_reader :relation

    def initialize(relation)
      if !relation.is_a?(ActiveRecord::Relation)
        raise ArgumentError, "relation is not an ActiveRecord::Relation"
      end

      @relation = relation
    end

    def each_batch(of: 1000, column: relation.primary_key, start: nil, finish: nil, order: :asc)
      if ![:asc, :desc].include?(order)
        raise ArgumentError, ":order must be :asc or :desc, got #{order.inspect}"
      end

      relation = apply_limits(self.relation, column, start, finish, order)

      base_relation = relation.except(:select)
        .select(column)
        .reorder(column => order)

      start_row = base_relation.uncached { base_relation.first }

      return if !start_row

      start_id = start_row[column]
      arel_table = relation.arel_table

      0.step do |index|
        if order == :asc
          start_cond = arel_table[column].gteq(start_id)
        else
          start_cond = arel_table[column].lteq(start_id)
        end

        stop_row = base_relation.uncached do
          base_relation
            .where(start_cond)
            .offset(of)
            .first
        end

        batch_relation = relation.where(start_cond)

        if stop_row
          stop_id = stop_row[column]
          start_id = stop_id

          if order == :asc
            stop_cond = arel_table[column].lt(stop_id)
          else
            stop_cond = arel_table[column].gt(stop_id)
          end

          batch_relation = batch_relation.where(stop_cond)
        end

        # Any ORDER BYs are useless for this relation and can lead to less
        # efficient UPDATE queries, hence we get rid of it.
        batch_relation = batch_relation.except(:order)

        # Retaining the results in the query cache would undermine the point of batching.
        batch_relation.uncached { yield batch_relation, index }

        break if !stop_row
      end
    end

    private
      def apply_limits(relation, column, start, finish, order)
        if start
          relation = relation.where(relation.arel_table[column].public_send((order == :asc ? :gteq : :lteq), start))
        end

        if finish
          relation = relation.where(relation.arel_table[column].public_send((order == :asc ? :lteq : :gteq), finish))
        end

        relation
      end
  end
end
