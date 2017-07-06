require 'csv'
require 'json'

patient_file = File.read("data/patients.json")
patient_data = JSON.parse(patient_file)

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
    else
      hospID_to_uuid[hospID] = uuid
    end
  end
end

patients_by_id = Hash.new
patient_data.each do |patient_record|
  patients_by_id[patient_record["id"]] = {
    "firstName" => patient_record["firstName"],
    "lastName" => patient_record["lastName"],
    "dob" => patient_record["dob"],
    "lab_results" => Hash.new
  }
end


=begin
{
  "patients" =>
    patients.map do |patient|
      {
        "id" => patient.id,
        "firstName" => patient.firstName,
        "lastName" => patient.lastName,
        "dob" => patient.dob,
        "lab_results" =>
          patient.lab_results.map do |result_group|
            {
              "timestamp" => result_group.timestamp,
              "profile" => {
                "name" => result_group.profile_name,
                "code" => result_group.profile_code
              },
              "panel" =>
                result_group.panel.map do |result|
                  {
                    "code" => result.code,
                    "label" => result.label,
                    "value" => result.value,
                    "unit" => result.unit,
                    "lower" => result.lower,
                    "upper" => result.upper
                  }
                end
            }
          end
      }
    end
}
=end