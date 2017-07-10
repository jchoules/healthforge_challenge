require 'csv'
require 'json'

def build_id_map(patient_data)
  # Map each hospital ID (used in labresults.csv)
  # to a uuid (used in patients.json)

  hospID_to_uuid = Hash.new
  patient_data.each do |patient_record|
    uuid = patient_record["id"]
    hospIDs = patient_record["identifiers"]
    next if hospIDs.nil?
    hospIDs.each do |hospID|
      # The hospital ID shouldn't already have
      # a different uuid associated with it
      if hospID_to_uuid.has_key?(hospID) and hospID_to_uuid[hospID] != uuid then
        raise "Patients with uuids #{uuid} and #{hospID_to_uuid[hospID]} "\
                "share the hospital ID #{hospID}."
      end
      hospID_to_uuid[hospID] = uuid
    end
  end

  return hospID_to_uuid
end

def build_patient_map(patient_data)
  patients_by_id = Hash.new
  patient_data.each do |patient_record|
    patients_by_id[patient_record["id"]] = {
      "firstName" => patient_record["firstName"],
      "lastName" => patient_record["lastName"],
      "dob" => patient_record["dateOfBirth"],
      "lab_results" => Hash.new
    }
  end

  return patients_by_id
end

def build_code_map(mapping_path)
  lab_code_to_snomed = Hash.new
  CSV.foreach(mapping_path, encoding: "UTF-8", headers: :first_row) do |row|
    lab_code_to_snomed[row["key"]] = {
      "code" => row["code"],
      "label" => row["description"]
    }
  end

  return lab_code_to_snomed
end

def load_results(results_path, patients_by_id, hospID_to_uuid, lab_code_to_snomed)
  CSV.foreach(results_path, encoding: "UTF-8", headers: :first_row) do |row|
    hospID = row["HospID"]
    next unless hospID_to_uuid.has_key?(hospID)

    uuid = hospID_to_uuid[hospID]
    panel_key = get_panel_key(row)
    result = get_result(row, lab_code_to_snomed)
    timestamp = DateTime.strptime(row["Date"], "%d/%m/%Y")

    results = patients_by_id[uuid]["lab_results"]
    unless results.has_key?(panel_key) then
      results[panel_key] = {
        "timestamp" => timestamp.strftime("%FT%T.%LZ"),
        "profile" => {
          "name" => row["Profile Name"],
          # Unfortunately the profile code header is also called
          # "Profile Name" and is thus shadowed by the preceding
          # header, but we can still access it via its numerical
          # index.
          "code" => row[4]
        },
        "panel" => [result]
      }
    else
      results[panel_key]["panel"] << result
    end
  end
end

def build_output_json(patients_by_id)
  return {
      "patients" =>
        patients_by_id.map do |patient_id, patient_data|
          {
            "id" => patient_id,
            "firstName" => patient_data["firstName"],
            "lastName" => patient_data["lastName"],
            "dob" => patient_data["dob"],
            "lab_results" =>
              patient_data["lab_results"].map do |_, panel_data|
                {
                  "timestamp" => panel_data["timestamp"],
                  "profile" => panel_data["profile"],
                  "panel" => panel_data["panel"]
                }
              end
          }
        end
  }
end

def get_panel_key(row)
  # The (somewhat naive and conservative) key chosen here is
  # an array comprising the patient's hospital ID, the date,
  # the code of the profile, and all 25 results (including the
  # empty ones).
  # SampleID is not included, since the specification
  # indicates that multiple samples may be tested in a single
  # panel.

  key = [row["HospID"], row["Date"], row[4]]
  1.upto(25) do |i|
    key << row["Res#{i}"]
  end

  #p key
  return key
end

def get_result(row, lab_code_to_snomed)
  hospital_code = row["TestName"]

  snomed_code = lab_code_to_snomed[hospital_code]["code"]
  snomed_label = lab_code_to_snomed[hospital_code]["label"]
  unit = row["Unit"]
  lower = row["Lower"].to_f
  upper = row["Upper"].to_f

  value = nil

  # Iterate through all the "ResN" cells until we find the
  # one with the corresponding code.
  1.upto(25) do |i|
    raw_reading = row["Res#{i}"]
    break if raw_reading.nil?
    current_code, current_value = raw_reading.split("~")
    if current_code == hospital_code then
      value = current_value.to_f
    end
  end

  if value.nil? then
    raise "Couldn't find result with code #{hospital_code} in row:\n#{row}"
  end

  return {
    "code" => snomed_code,
    "label" => snomed_label,
    "value" => value,
    "unit" => unit,
    "lower" => lower,
    "upper" => upper
  }
end

patient_file_path = "data/patients.json"
results_file_path = "data/labresults.csv"
code_mapping_file_path = "data/labresults-codes.csv"

output_file_path = "data/output.json"

patient_file = File.read(patient_file_path)
patient_json = JSON.parse(patient_file)

hospID_to_uuid = build_id_map(patient_json)
patients_by_id = build_patient_map(patient_json)
lab_code_to_snomed = build_code_map(code_mapping_file_path)

puts "Loading results..."

load_results(results_file_path, patients_by_id, hospID_to_uuid, lab_code_to_snomed)

output_json = build_output_json(patients_by_id)
output_text = JSON.pretty_generate(output_json)

File.open(output_file_path, "w") do |f|
  f.write(output_text)
end