# Copyright 2016 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


require "google/cloud/spanner/convert"
require "google/cloud/errors"

module Google
  module Cloud
    module Spanner
      ##
      # # Results
      #
      class Results
        ##
        # Indicates the field names and types for the rows in the returned data.
        #
        # @return [Hash] The types of the returned data.
        #
        # @example
        #   require "google/cloud/spanner"
        #
        #   spanner = Google::Cloud::Spanner.new
        #
        #   db = spanner.client "my-instance", "my-database"
        #
        #   results = db.execute "SELECT * FROM users"
        #
        #   results.types.each do |name, type|
        #     puts "Column #{name} is type {type}"
        #   end
        #
        def types
          row_types = @metadata.row_type.fields
          Hash[row_types.map do |field|
            # raise field.inspect
            if field.type.code == :ARRAY
              [field.name.to_sym, [field.type.array_element_type.code]]
            else
              [field.name.to_sym, field.type.code]
            end
          end]
        end

        # rubocop:disable all

        ##
        # The values returned from the request.
        #
        # @yield [rows] An enumerator for the rows.
        # @yieldparam [Hash] rows the hash that contains the result names and
        #   values.
        #
        # @example
        #   require "google/cloud/spanner"
        #
        #   spanner = Google::Cloud::Spanner.new
        #
        #   db = spanner.client "my-instance", "my-database"
        #
        #   results = db.execute "SELECT * FROM users"
        #
        #   results.rows.each do |row|
        #     puts "User #{row[:id]} is #{row[:name]}""
        #   end
        #
        def rows
          return @rows.to_enum if @rows

          return nil if @closed

          unless block_given?
            return enum_for(:rows)
          end

          fields = @metadata.row_type.fields
          values = []
          buffered_responses = []
          buffer_upper_bound = 10
          chunked_value = nil
          resume_token = nil

          # Cannot call Enumerator#each because it won't return the first
          # value that was already identified when calling Enumerator#peek.
          # Iterate only using Enumerator#next and break on StopIteration.
          loop do
            begin
              grpc = @enum.next
              # metadata should be set before the first iteration...
              @metadata ||= grpc.metadata
              @stats ||= grpc.stats

              buffered_responses << grpc

              if (grpc.resume_token && grpc.resume_token != "") ||
                buffered_responses.size >= buffer_upper_bound
                # This can set the resume_token to nil
                resume_token = grpc.resume_token

                buffered_responses.each do |resp|
                  if chunked_value
                    resp.values.unshift merge(chunked_value, resp.values.shift)
                    chunked_value = nil
                  end
                  to_iterate = values + Array(resp.values)
                  chunked_value = to_iterate.pop if resp.chunked_value
                  values = to_iterate.pop(to_iterate.count % fields.count)
                  to_iterate.each_slice(fields.count) do |slice|
                    yield Convert.row_to_raw(fields, slice)
                  end
                end

                # Flush the buffered responses now that they are all handled
                buffered_responses = []
              end
            rescue GRPC::Aborted => aborted
              if resume_token.nil? || resume_token.empty?
                # Re-raise if the resume_token is not a valid value.
                # This can happen if the buffer was flushed.
                raise Google::Cloud::Error.from_error(aborted)
              end

              # Resume the stream from the last known resume_token
              if @execute_options
                @enum = @service.streaming_execute_sql \
                  @session_path, @sql,
                  @execute_options.merge(resume_token: resume_token)
              else
                @enum = @service.streaming_read_table \
                  @session_path, @table, @columns,
                  @read_options.merge(resume_token: resume_token)
              end

              # Flush the buffered responses to reset to the resume_token
              buffered_responses = []
            rescue StopIteration
              break
            end
          end

          # clear out any remaining values left over
          buffered_responses.each do |resp|
            if chunked_value
              resp.values.unshift merge(chunked_value, resp.values.shift)
              chunked_value = nil
            end
            to_iterate = values + Array(resp.values)
            chunked_value = to_iterate.pop if resp.chunked_value
            values = to_iterate.pop(to_iterate.count % fields.count)
            to_iterate.each_slice(fields.count) do |slice|
              yield Convert.row_to_raw(fields, slice)
            end
          end
          values.each_slice(fields.count) do |slice|
            yield Convert.row_to_raw(fields, slice)
          end

          # If we get this far then we can release the session
          @closed = true
          nil
        end

        # rubocop:enable all

        ##
        # Whether the returned data is streaming from the Spanner API.
        # @return [Boolean]
        def streaming?
          !@enum.nil?
        end

        # @private
        def self.from_grpc grpc
          results = new
          rows = grpc.rows.map do |row|
            Convert.row_to_raw grpc.metadata.row_type.fields, row.values
          end
          results.instance_variable_set :@metadata, grpc.metadata
          results.instance_variable_set :@rows,     rows
          results.instance_variable_set :@stats,    grpc.stats
          results
        end

        # @private
        def self.from_enum enum, service
          grpc = enum.peek
          new.tap do |results|
            results.instance_variable_set :@metadata, grpc.metadata
            results.instance_variable_set :@stats,    grpc.stats
            results.instance_variable_set :@enum,     enum
            results.instance_variable_set :@service,  service
          end
        end

        # @private
        def self.execute service, session_path, sql, params: nil,
                         transaction: nil
          execute_options = { transaction: transaction, params: params }
          enum = service.streaming_execute_sql session_path, sql,
                                               execute_options
          from_enum(enum, service).tap do |results|
            results.instance_variable_set :@session_path,    session_path
            results.instance_variable_set :@sql,             sql
            results.instance_variable_set :@execute_options, execute_options
          end
        end

        # @private
        def self.read service, session_path, table, columns, id: nil,
                      limit: nil, transaction: nil
          read_options = { id: id, limit: limit, transaction: transaction }
          enum = service.streaming_read_table \
            session_path, table, columns, read_options
          from_enum(enum, service).tap do |results|
            results.instance_variable_set :@session_path, session_path
            results.instance_variable_set :@table,        table
            results.instance_variable_set :@columns,      columns
            results.instance_variable_set :@read_options, read_options
          end
        end

        # @private
        def to_s
          if streaming?
            "#<#{self.class.name} (types: #{types.inspect} streaming)>"
          else
            "#<#{self.class.name} (" \
              "(types: #{types.inspect}, rows: #{rows.count})>"
          end
        end

        # @private
        def inspect
          "#<#{self.class.name} #{self}>"
        end

        protected

        # rubocop:disable all

        # @private
        def merge left, right
          if left.kind != right.kind
            raise "Can't merge #{left.kind} and #{right.kind} values"
          end
          if left.kind == :string_value
            left.string_value = left.string_value + right.string_value
            return left
          elsif left.kind == :list_value
            left_val = left.list_value.values.pop
            right_val = right.list_value.values.shift
            if left_val.kind == :string_value && right_val.kind == :string_value
              left.list_value.values << merge(left_val, right_val)
            else
              left.list_value.values << left_val
              left.list_value.values << right_val
            end
            right.list_value.values.each { |val| left.list_value.values << val }
            return left
          elsif left.kind == :struct_value
            # Don't worry about this yet since Spanner isn't return STRUCT
            fail "STRUCT not implemented yet"
          else
            raise "Can't merge #{left.kind} values"
          end
        end

        # rubocop:enable all
      end
    end
  end
end
