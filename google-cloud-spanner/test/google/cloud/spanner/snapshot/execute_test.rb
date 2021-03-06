# Copyright 2017 Google Inc. All rights reserved.
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

require "helper"

describe Google::Cloud::Spanner::Snapshot, :execute, :mock_spanner do
  let(:instance_id) { "my-instance-id" }
  let(:database_id) { "my-database-id" }
  let(:session_id) { "session123" }
  let(:session_grpc) { Google::Spanner::V1::Session.new name: session_path(instance_id, database_id, session_id) }
  let(:session) { Google::Cloud::Spanner::Session.from_grpc session_grpc, spanner.service }
  let(:transaction_id) { "tx789" }
  let(:transaction_grpc) { Google::Spanner::V1::Transaction.new id: transaction_id }
  let(:snapshot) { Google::Cloud::Spanner::Snapshot.from_grpc transaction_grpc, session }
  let(:tx_selector) { Google::Spanner::V1::TransactionSelector.new id: transaction_id }
  let(:default_options) { Google::Gax::CallOptions.new kwargs: { "google-cloud-resource-prefix" => database_path(instance_id, database_id) } }
  let :results_hash do
    {
      metadata: {
        rowType: {
          fields: [
            { name: "id",          type: { code: "INT64" } },
            { name: "name",        type: { code: "STRING" } },
            { name: "active",      type: { code: "BOOL" } },
            { name: "age",         type: { code: "INT64" } },
            { name: "score",       type: { code: "FLOAT64" } },
            { name: "updated_at",  type: { code: "TIMESTAMP" } },
            { name: "birthday",    type: { code: "DATE"} },
            { name: "avatar",      type: { code: "BYTES" } },
            { name: "project_ids", type: { code: "ARRAY",
                                           arrayElementType: { code: "INT64" } } }
          ]
        }
      },
     rows: [{
        values: [
          { stringValue: "1" },
          { stringValue: "Charlie" },
          { boolValue: true},
          { stringValue: "29" },
          { numberValue: 0.9 },
          { stringValue: "2017-01-02T03:04:05.060000000Z" },
          { stringValue: "1950-01-01" },
          { stringValue: "aW1hZ2U=" },
          { listValue: { values: [ { stringValue: "1"},
                                   { stringValue: "2"},
                                   { stringValue: "3"} ]}}
        ]
      }
    ]}
  end
  let(:results_json) { results_hash.to_json }
  let(:results_grpc) { Google::Spanner::V1::ResultSet.decode_json results_json }

  it "can execute a simple query" do
    mock = Minitest::Mock.new
    mock.expect :execute_sql, results_grpc, [session.path, "SELECT * FROM users", transaction: tx_selector, params: nil, param_types: nil, options: default_options]
    session.service.mocked_service = mock

    results = snapshot.execute "SELECT * FROM users", streaming: false

    mock.verify

    assert_results results
  end

  it "can execute sql using the query alias" do
    mock = Minitest::Mock.new
    mock.expect :execute_sql, results_grpc, [session.path, "SELECT * FROM users", transaction: tx_selector, params: nil, param_types: nil, options: default_options]
    session.service.mocked_service = mock

    results = snapshot.query "SELECT * FROM users", streaming: false

    mock.verify

    assert_results results
  end

  it "can execute a query with bool param" do
    mock = Minitest::Mock.new
    mock.expect :execute_sql, results_grpc, [session.path, "SELECT * FROM users WHERE active = @active", transaction: tx_selector, params: Google::Protobuf::Struct.new(fields: { "active" => Google::Protobuf::Value.new(bool_value: true) }), param_types: { "active" => Google::Spanner::V1::Type.new(code: :BOOL) }, options: default_options]
    session.service.mocked_service = mock

    results = snapshot.execute "SELECT * FROM users WHERE active = @active", params: { active: true }, streaming: false

    mock.verify

    assert_results results
  end

  it "can execute a query with int param" do
    mock = Minitest::Mock.new
    mock.expect :execute_sql, results_grpc, [session.path, "SELECT * FROM users WHERE age = @age", transaction: tx_selector, params: Google::Protobuf::Struct.new(fields: { "age" => Google::Protobuf::Value.new(string_value: "29") }), param_types: { "age" => Google::Spanner::V1::Type.new(code: :INT64) }, options: default_options]
    session.service.mocked_service = mock

    results = snapshot.execute "SELECT * FROM users WHERE age = @age", params: { age: 29 }, streaming: false

    mock.verify

    assert_results results
  end

  it "can execute a query with float param" do
    mock = Minitest::Mock.new
    mock.expect :execute_sql, results_grpc, [session.path, "SELECT * FROM users WHERE score = @score", transaction: tx_selector, params: Google::Protobuf::Struct.new(fields: { "score" => Google::Protobuf::Value.new(number_value: 0.9) }), param_types: { "score" => Google::Spanner::V1::Type.new(code: :FLOAT64) }, options: default_options]
    session.service.mocked_service = mock

    results = snapshot.execute "SELECT * FROM users WHERE score = @score", params: { score: 0.9 }, streaming: false

    mock.verify

    assert_results results
  end

  it "can execute a query with Time param" do
    timestamp = Time.parse "2017-01-01 20:04:05.06 -0700"

    mock = Minitest::Mock.new
    mock.expect :execute_sql, results_grpc, [session.path, "SELECT * FROM users WHERE updated_at = @updated_at", transaction: tx_selector, params: Google::Protobuf::Struct.new(fields: { "updated_at" => Google::Protobuf::Value.new(string_value: "2017-01-02T03:04:05.060000000Z") }), param_types: { "updated_at" => Google::Spanner::V1::Type.new(code: :TIMESTAMP) }, options: default_options]
    session.service.mocked_service = mock

    results = snapshot.execute "SELECT * FROM users WHERE updated_at = @updated_at", params: { updated_at: timestamp }, streaming: false

    mock.verify

    assert_results results
  end

  it "can execute a query with Date param" do
    date = Date.parse "2017-01-02"

    mock = Minitest::Mock.new
    mock.expect :execute_sql, results_grpc, [session.path, "SELECT * FROM users WHERE birthday = @birthday", transaction: tx_selector, params: Google::Protobuf::Struct.new(fields: { "birthday" => Google::Protobuf::Value.new(string_value: "2017-01-02") }), param_types: { "birthday" => Google::Spanner::V1::Type.new(code: :DATE) }, options: default_options]
    session.service.mocked_service = mock

    results = snapshot.execute "SELECT * FROM users WHERE birthday = @birthday", params: { birthday: date }, streaming: false

    mock.verify

    assert_results results
  end

  it "can execute a query with String param" do
    mock = Minitest::Mock.new
    mock.expect :execute_sql, results_grpc, [session.path, "SELECT * FROM users WHERE name = @name", transaction: tx_selector, params: Google::Protobuf::Struct.new(fields: { "name" => Google::Protobuf::Value.new(string_value: "Charlie") }), param_types: { "name" => Google::Spanner::V1::Type.new(code: :STRING) }, options: default_options]
    session.service.mocked_service = mock

    results = snapshot.execute "SELECT * FROM users WHERE name = @name", params: { name: "Charlie" }, streaming: false

    mock.verify

    assert_results results
  end

  it "can execute a query with IO-ish param" do
    file = StringIO.new "contents"

    mock = Minitest::Mock.new
    mock.expect :execute_sql, results_grpc, [session.path, "SELECT * FROM users WHERE avatar = @avatar", transaction: tx_selector, params: Google::Protobuf::Struct.new(fields: { "avatar" => Google::Protobuf::Value.new(string_value: Base64.strict_encode64("contents")) }), param_types: { "avatar" => Google::Spanner::V1::Type.new(code: :BYTES) }, options: default_options]
    session.service.mocked_service = mock

    results = snapshot.execute "SELECT * FROM users WHERE avatar = @avatar", params: { avatar: file }, streaming: false

    mock.verify

    assert_results results
  end

  it "can execute a query with an Array param" do
    mock = Minitest::Mock.new
    mock.expect :execute_sql, results_grpc, [session.path, "SELECT * FROM users WHERE project_ids = @list", transaction: tx_selector, params: Google::Protobuf::Struct.new(fields: { "list" => Google::Protobuf::Value.new(list_value: Google::Protobuf::ListValue.new(values: [Google::Protobuf::Value.new(string_value: "1"), Google::Protobuf::Value.new(string_value: "2"), Google::Protobuf::Value.new(string_value: "3")])) }), param_types: { "list" => Google::Spanner::V1::Type.new(code: :ARRAY, array_element_type: Google::Spanner::V1::Type.new(code: :INT64)) }, options: default_options]
    session.service.mocked_service = mock

    results = snapshot.execute "SELECT * FROM users WHERE project_ids = @list", params: { list: [1,2,3] }, streaming: false

    mock.verify

    assert_results results
  end

  it "can execute a query with an empty Array param" do
    mock = Minitest::Mock.new
    mock.expect :execute_sql, results_grpc, [session.path, "SELECT * FROM users WHERE project_ids = @list", transaction: tx_selector, params: Google::Protobuf::Struct.new(fields: { "list" => Google::Protobuf::Value.new(list_value: Google::Protobuf::ListValue.new(values: [])) }), param_types: { "list" => Google::Spanner::V1::Type.new(code: :ARRAY, array_element_type: Google::Spanner::V1::Type.new(code: :INT64)) }, options: default_options]
    session.service.mocked_service = mock

    results = snapshot.execute "SELECT * FROM users WHERE project_ids = @list", params: { list: [] }, streaming: false

    mock.verify

    assert_results results
  end

  it "can execute a query with a simple Hash param" do
    skip "Spanner does not accept STRUCT values in query parameters"

    mock = Minitest::Mock.new
    mock.expect :execute_sql, results_grpc, [session.path, "SELECT * FROM users WHERE settings = @dict", transaction: tx_selector, params: Google::Protobuf::Struct.new(fields: { "dict" => Google::Protobuf::Value.new(struct_value: Google::Protobuf::Struct.new(fields: {"env"=>Google::Protobuf::Value.new(string_value: "production")})) }), param_types: { "dict" => Google::Spanner::V1::Type.new(code: :STRUCT, struct_type: Google::Spanner::V1::StructType.new(fields: [Google::Spanner::V1::StructType::Field.new(name: "env", type: Google::Spanner::V1::Type.new(code: :STRING))])) }, options: default_options]
    session.service.mocked_service = mock

    results = snapshot.execute "SELECT * FROM users WHERE settings = @dict", params: { dict: { env: :production } }, streaming: false

    mock.verify

    assert_results results
  end

  it "can execute a query with a complex Hash param" do
    skip "Spanner does not accept STRUCT values in query parameters"

    mock = Minitest::Mock.new
    mock.expect :execute_sql, results_grpc, [session.path, "SELECT * FROM users WHERE settings = @dict", transaction: tx_selector, params: Google::Protobuf::Struct.new(fields: { "dict" => Google::Protobuf::Value.new(struct_value: Google::Protobuf::Struct.new(fields: { "score" => Google::Protobuf::Value.new(number_value: 0.9), "env" => Google::Protobuf::Value.new(string_value: "production"), "project_ids" => Google::Protobuf::Value.new(list_value: Google::Protobuf::ListValue.new(values: [Google::Protobuf::Value.new(string_value: "1"), Google::Protobuf::Value.new(string_value: "2"), Google::Protobuf::Value.new(string_value: "3")] )) })) }), param_types: { "dict" => Google::Spanner::V1::Type.new(code: :STRUCT, struct_type: Google::Spanner::V1::StructType.new(fields: [Google::Spanner::V1::StructType::Field.new(name: "env", type: Google::Spanner::V1::Type.new(code: :STRING)), Google::Spanner::V1::StructType::Field.new(name: "score", type: Google::Spanner::V1::Type.new(code: :FLOAT64)), Google::Spanner::V1::StructType::Field.new(name: "project_ids", type: Google::Spanner::V1::Type.new(code: :ARRAY, array_element_type: Google::Spanner::V1::Type.new(code: :INT64)))] )) }, options: default_options]
    session.service.mocked_service = mock

    results = snapshot.execute "SELECT * FROM users WHERE settings = @dict", params: { dict: { env: "production", score: 0.9, project_ids: [1,2,3] } }, streaming: false

    mock.verify

    assert_results results
  end

  it "can execute a query with an empty Hash param" do
    skip "Spanner does not accept STRUCT values in query parameters"

    mock = Minitest::Mock.new
    mock.expect :execute_sql, results_grpc, [session.path, "SELECT * FROM users WHERE settings = @dict", transaction: tx_selector, params: Google::Protobuf::Struct.new(fields: { "dict" => Google::Protobuf::Value.new(struct_value: Google::Protobuf::Struct.new(fields: {})) }), param_types: { "dict" => Google::Spanner::V1::Type.new(code: :STRUCT, struct_type: Google::Spanner::V1::StructType.new(fields: [])) }, options: default_options]
    session.service.mocked_service = mock

    results = snapshot.execute "SELECT * FROM users WHERE settings = @dict", params: { dict: { } }, streaming: false

    mock.verify

    assert_results results
  end

  def assert_results results
    results.must_be_kind_of Google::Cloud::Spanner::Results
    results.wont_be :streaming?

    results.types.wont_be :nil?
    results.types.must_be_kind_of Hash
    results.types.keys.count.must_equal 9
    results.types[:id].must_equal          :INT64
    results.types[:name].must_equal        :STRING
    results.types[:active].must_equal      :BOOL
    results.types[:age].must_equal         :INT64
    results.types[:score].must_equal       :FLOAT64
    results.types[:updated_at].must_equal  :TIMESTAMP
    results.types[:birthday].must_equal    :DATE
    results.types[:avatar].must_equal      :BYTES
    results.types[:project_ids].must_equal [:INT64]

    results.rows.count.must_equal 1
    row = results.rows.first
    row.must_be_kind_of Hash
    row.keys.must_equal [:id, :name, :active, :age, :score, :updated_at, :birthday, :avatar, :project_ids]
    row[:id].must_equal 1
    row[:name].must_equal "Charlie"
    row[:active].must_equal true
    row[:age].must_equal 29
    row[:score].must_equal 0.9
    row[:updated_at].must_equal Time.parse("2017-01-02T03:04:05.060000000Z")
    row[:birthday].must_equal Date.parse("1950-01-01")
    row[:avatar].must_be_kind_of StringIO
    row[:avatar].read.must_equal "image"
    row[:project_ids].must_equal [1, 2, 3]
  end
end
