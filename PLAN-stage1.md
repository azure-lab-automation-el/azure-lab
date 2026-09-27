# Esther plan - stage 1 (org structure)

Merging this PR = approving exactly these 225 changes. esther-apply refuses to run if live Entra no longer produces this same plan (desired-state/reviewed-plan.json). No users are created or deleted. UPNs are not changed here (that is stage 2, a separate PR).

| Change | Count |
|---|---|
| renameGroup | 4 |
| updateUser | 100 |
| setManager | 99 |
| removeMember | 11 |
| addMember | 11 |

## Group renames
- Esther Hospital - Radiology -> Esther Hospital - Imaging
- Esther Hospital - Pediatrics -> Esther Hospital - Admissions
- Esther Hospital - Surgery -> Esther Hospital - Finance
- Esther Hospital - Pharmacy -> Esther Hospital - IT

## Department moves (group membership)
- Rotem Avni: Finance -> Emergency
- Roni Halperin: Facilities -> Nursing
- Or Avni: Finance -> Nursing
- Shahar Carmel: IT -> Nursing
- Yarden Gefen: Oncology -> Nursing
- Roni Avni: Neurology -> Nursing
- Tamar Avni: Administration -> Nursing
- Tal Halperin: Facilities -> Nursing
- Omer Harari: Cardiology -> Nursing
- Maya Avni: Admissions -> Nursing
- Amit Naveh: Finance -> Nursing

## People (department, title, manager)
| Name | Department | Title (before -> after) | Manager |
|---|---|---|---|
| Or Shalev | Administration | Hospital Administration Coordinator -> Chief Executive Officer | (none - top) |
| Yael Gefen | Administration | Hospital Administration Coordinator -> Chief Operating Officer | Or Shalev |
| Adi Kedem | Administration | Hospital Administration Coordinator -> Human Resources Manager | Or Shalev |
| Adi Gefen | Administration | Hospital Administration Coordinator -> Executive Assistant | Or Shalev |
| Yuval Barak | Administration | Hospital Administration Coordinator -> Office Manager | Or Shalev |
| Shahar Kedem | Administration | Hospital Administration Coordinator -> Quality Assurance Coordinator | Or Shalev |
| Gal Talmon | Administration | Hospital Administration Coordinator -> Patient Relations Officer | Or Shalev |
| Neta Talmon | Emergency | Emergency Care Coordinator -> Head of Emergency Medicine | Or Shalev |
| Adi Carmel | Emergency | Emergency Care Coordinator -> Senior Emergency Physician | Neta Talmon |
| Noam Shavit | Emergency | Emergency Care Coordinator -> Emergency Physician | Neta Talmon |
| Amit Halperin | Emergency | Emergency Care Coordinator -> Emergency Nurse | Neta Talmon |
| Yael Raz | Emergency | Emergency Care Coordinator -> Triage Nurse | Neta Talmon |
| Hila Talmon | Emergency | Emergency Care Coordinator -> Paramedic | Neta Talmon |
| Tamar Naveh | Emergency | Emergency Care Coordinator -> Emergency Resident | Neta Talmon |
| Omer Barak | Emergency | Emergency Care Coordinator -> Emergency Department Clerk | Neta Talmon |
| Yael Kedem | Emergency | Emergency Care Coordinator -> Senior Emergency Physician | Neta Talmon |
| Rotem Avni | Surgery -> Emergency | Surgical Services Specialist -> Emergency Physician | Neta Talmon |
| Noam Avni | Cardiology | Cardiology Care Specialist -> Head of Cardiology | Or Shalev |
| Gal Paz | Cardiology | Cardiology Care Specialist -> Senior Cardiologist | Noam Avni |
| Yarden Carmel | Cardiology | Cardiology Care Specialist -> Cardiologist | Noam Avni |
| Tal Shavit | Cardiology | Cardiology Care Specialist -> Cardiac Nurse | Noam Avni |
| Dana Barak | Cardiology | Cardiology Care Specialist -> Echocardiography Technician | Noam Avni |
| Roni Dror | Cardiology | Cardiology Care Specialist -> Cardiology Resident | Noam Avni |
| Neta Paz | Cardiology | Cardiology Care Specialist -> Cath Lab Technician | Noam Avni |
| Lior Paz | Cardiology | Cardiology Care Specialist -> Senior Cardiologist | Noam Avni |
| Yuval Doron | Neurology | Neurology Services Specialist -> Head of Neurology | Or Shalev |
| Or Shavit | Neurology | Neurology Services Specialist -> Senior Neurologist | Yuval Doron |
| Tal Avni | Neurology | Neurology Services Specialist -> Neurologist | Yuval Doron |
| Neta Ilan | Neurology | Neurology Services Specialist -> Neurology Nurse | Yuval Doron |
| Erez Talmon | Neurology | Neurology Services Specialist -> EEG Technician | Yuval Doron |
| Yarden Raz | Neurology | Neurology Services Specialist -> Neurology Resident | Yuval Doron |
| Amit Shavit | Neurology | Neurology Services Specialist -> Senior Neurologist | Yuval Doron |
| Neta Doron | Oncology | Oncology Care Coordinator -> Head of Oncology | Or Shalev |
| Tamar Halperin | Oncology | Oncology Care Coordinator -> Senior Oncologist | Neta Doron |
| Gal Ilan | Oncology | Oncology Care Coordinator -> Oncologist | Neta Doron |
| Noam Naveh | Oncology | Oncology Care Coordinator -> Oncology Nurse | Neta Doron |
| Roni Naveh | Oncology | Oncology Care Coordinator -> Radiation Therapist | Neta Doron |
| Amit Dror | Oncology | Oncology Care Coordinator -> Oncology Social Worker | Neta Doron |
| Dana Harari | Oncology | Oncology Care Coordinator -> Senior Oncologist | Neta Doron |
| Rotem Dror | Nursing | Nursing Care Specialist -> Director of Nursing | Or Shalev |
| Neta Harari | Nursing | Nursing Care Specialist -> Head Nurse | Rotem Dror |
| Rotem Shavit | Nursing | Nursing Care Specialist -> Charge Nurse | Rotem Dror |
| Maya Dror | Nursing | Nursing Care Specialist -> Registered Nurse | Rotem Dror |
| Gal Harari | Nursing | Nursing Care Specialist -> Registered Nurse | Rotem Dror |
| Tal Dror | Nursing | Nursing Care Specialist -> Practical Nurse | Rotem Dror |
| Maya Shalev | Nursing | Nursing Care Specialist -> Nursing Assistant | Rotem Dror |
| Roni Shavit | Nursing | Nursing Care Specialist -> Nurse Educator | Rotem Dror |
| Roni Halperin | Facilities -> Nursing | Facilities Operations Specialist -> Clinical Nurse Specialist | Rotem Dror |
| Or Avni | Surgery -> Nursing | Surgical Services Specialist -> Head Nurse | Rotem Dror |
| Shahar Carmel | Pharmacy -> Nursing | Pharmacy Operations Coordinator -> Charge Nurse | Rotem Dror |
| Yarden Gefen | Oncology -> Nursing | Oncology Care Coordinator -> Registered Nurse | Rotem Dror |
| Roni Avni | Neurology -> Nursing | Neurology Services Specialist -> Registered Nurse | Rotem Dror |
| Tamar Avni | Administration -> Nursing | Hospital Administration Coordinator -> Practical Nurse | Rotem Dror |
| Tal Halperin | Facilities -> Nursing | Facilities Operations Specialist -> Nursing Assistant | Rotem Dror |
| Omer Harari | Cardiology -> Nursing | Cardiology Care Specialist -> Nurse Educator | Rotem Dror |
| Maya Avni | Pediatrics -> Nursing | Pediatric Care Coordinator -> Clinical Nurse Specialist | Rotem Dror |
| Amit Naveh | Surgery -> Nursing | Surgical Services Specialist -> Head Nurse | Rotem Dror |
| Hila Paz | Laboratory | Laboratory Services Specialist -> Laboratory Manager | Or Shalev |
| Dana Talmon | Laboratory | Laboratory Services Specialist -> Senior Lab Scientist | Hila Paz |
| Erez Harari | Laboratory | Laboratory Services Specialist -> Medical Lab Scientist | Hila Paz |
| Shahar Gefen | Laboratory | Laboratory Services Specialist -> Lab Technician | Hila Paz |
| Lior Harari | Laboratory | Laboratory Services Specialist -> Phlebotomist | Hila Paz |
| Omer Doron | Laboratory | Laboratory Services Specialist -> Pathology Assistant | Hila Paz |
| Yuval Talmon | Laboratory | Laboratory Services Specialist -> Senior Lab Scientist | Hila Paz |
| Yarden Zohar | Laboratory | Laboratory Services Specialist -> Medical Lab Scientist | Hila Paz |
| Shahar Zohar | Radiology -> Imaging | Imaging Services Coordinator -> Head of Imaging | Or Shalev |
| Dana Paz | Radiology -> Imaging | Imaging Services Coordinator -> Senior Radiologist | Shahar Zohar |
| Tamar Shavit | Radiology -> Imaging | Imaging Services Coordinator -> Radiologist | Shahar Zohar |
| Maya Naveh | Radiology -> Imaging | Imaging Services Coordinator -> Radiographer | Shahar Zohar |
| Omer Talmon | Radiology -> Imaging | Imaging Services Coordinator -> MRI Technologist | Shahar Zohar |
| Erez Ilan | Radiology -> Imaging | Imaging Services Coordinator -> CT Technologist | Shahar Zohar |
| Adi Zohar | Radiology -> Imaging | Imaging Services Coordinator -> Ultrasound Technician | Shahar Zohar |
| Yuval Harari | Radiology -> Imaging | Imaging Services Coordinator -> Senior Radiologist | Shahar Zohar |
| Lior Doron | Pediatrics -> Admissions | Pediatric Care Coordinator -> Admissions Manager | Or Shalev |
| Hila Doron | Pediatrics -> Admissions | Pediatric Care Coordinator -> Admissions Supervisor | Lior Doron |
| Dana Doron | Pediatrics -> Admissions | Pediatric Care Coordinator -> Admissions Clerk | Lior Doron |
| Maya Shavit | Pediatrics -> Admissions | Pediatric Care Coordinator -> Patient Registration Clerk | Lior Doron |
| Or Naveh | Pediatrics -> Admissions | Pediatric Care Coordinator -> Bed Management Coordinator | Lior Doron |
| Hila Ilan | Pediatrics -> Admissions | Pediatric Care Coordinator -> Front Desk Representative | Lior Doron |
| Yuval Paz | Pediatrics -> Admissions | Pediatric Care Coordinator -> Admissions Supervisor | Lior Doron |
| Amit Avni | Pediatrics -> Admissions | Pediatric Care Coordinator -> Admissions Clerk | Lior Doron |
| Omer Paz | Surgery -> Finance | Surgical Services Specialist -> Finance Manager | Or Shalev |
| Noam Shalev | Surgery -> Finance | Surgical Services Specialist -> Senior Accountant | Omer Paz |
| Adi Raz | Surgery -> Finance | Surgical Services Specialist -> Accountant | Omer Paz |
| Shahar Raz | Surgery -> Finance | Surgical Services Specialist -> Billing Specialist | Omer Paz |
| Lior Talmon | Surgery -> Finance | Surgical Services Specialist -> Payroll Specialist | Omer Paz |
| Rotem Naveh | Surgery -> Finance | Surgical Services Specialist -> Procurement Officer | Omer Paz |
| Rotem Shalev | Pharmacy -> IT | Pharmacy Operations Coordinator -> IT Manager | Or Shalev |
| Noam Dror | Pharmacy -> IT | Pharmacy Operations Coordinator -> Systems Administrator | Rotem Shalev |
| Or Dror | Pharmacy -> IT | Pharmacy Operations Coordinator -> Network Engineer | Rotem Shalev |
| Yael Carmel | Pharmacy -> IT | Pharmacy Operations Coordinator -> Help Desk Technician | Rotem Shalev |
| Erez Paz | Pharmacy -> IT | Pharmacy Operations Coordinator -> Clinical Applications Analyst | Rotem Shalev |
| Yael Zohar | Pharmacy -> IT | Pharmacy Operations Coordinator -> Security Analyst | Rotem Shalev |
| Yarden Kedem | Pharmacy -> IT | Pharmacy Operations Coordinator -> Systems Administrator | Rotem Shalev |
| Hila Harari | Facilities | Facilities Operations Specialist -> Facilities Manager | Or Shalev |
| Erez Doron | Facilities | Facilities Operations Specialist -> Maintenance Supervisor | Hila Harari |
| Tamar Dror | Facilities | Facilities Operations Specialist -> Electrician | Hila Harari |
| Gal Doron | Facilities | Facilities Operations Specialist -> HVAC Technician | Hila Harari |
| Lior Barak | Facilities | Facilities Operations Specialist -> Maintenance Technician | Hila Harari |
| Tal Naveh | Facilities | Facilities Operations Specialist -> Housekeeping Supervisor | Hila Harari |
