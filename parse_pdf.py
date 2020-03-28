import PyPDF2
from tabula import read_pdf
from urllib.parse import urlparse

#
# pdf = open("./temp/covid-19-case-report-3-27-2020.pdf", "rb")
#
# reader = PyPDF2.PdfFileReader(pdf)
#
# print(reader.numPages)
#
# page_1 = reader.getPage(0)
#
# print(page_1.extractText())
#
# pdf.close()

df = read_pdf("./temp/covid-19-case-report-3-27-2020.pdf")

print(df)