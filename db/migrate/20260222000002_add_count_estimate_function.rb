# frozen_string_literal: true

class AddCountEstimateFunction < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION count_estimate(query text) RETURNS integer AS $$
      DECLARE
        rec record;
        rows integer;
      BEGIN
        FOR rec IN EXECUTE 'EXPLAIN ' || query LOOP
          rows := substring(rec."QUERY PLAN" FROM 'rows=([[:digit:]]+)')::integer;
          EXIT;
        END LOOP;
        RETURN rows;
      END;
      $$ LANGUAGE plpgsql VOLATILE STRICT;
    SQL
  end

  def down
    execute "DROP FUNCTION IF EXISTS count_estimate(text);"
  end
end
