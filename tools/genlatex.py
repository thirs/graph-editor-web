#print(" Pour que ça marche il faut firefox et ajouter geckodriver soit dans PATH")
print("This python3 script requires the selenium geckodriver (https://selenium-python.readthedocs.io/installation.html#drivers)")
print("Other requirements: the in_place package")
print()



from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.common.exceptions import TimeoutException
from selenium.common.exceptions import ElementNotInteractableException
from selenium.common.exceptions import UnexpectedAlertPresentException
from selenium.webdriver.common.desired_capabilities import DesiredCapabilities
from selenium.webdriver.support.ui import Select
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.common.action_chains import ActionChains
from selenium.webdriver.support.ui import WebDriverWait
from os.path import exists
from collections import namedtuple

Diag = namedtuple('Diag' , 'content isFile isEdit isNew isGenerate')
Command = namedtuple('Command' , 'content prefix command')

import sys
import re
import in_place

MAGIC_STRING = "YADE DIAGRAM"
URL_YADE = 'https://amblafont.github.io/graph-editor/index.html'

if(len(sys.argv) != 2):
    print('Usage: %s filename' % sys.argv[0])
    print()
    print("This script looks for lines ending with YADE DIAGRAM '[commands] [diagram]")
    print("where")
    print("- [diagram] is empty, a json encoded diagram (pasted from the editor by using C-c on some selected diagram, or from the content of a saved file) or a filename")
    print("- [commands] is either n (for new), e (for edit), g (for latex generation), or eg (edit and generation) ")
    print("(a new diagram is always edited)")
    print("When LaTeX generation is required, the script loads the diagram in the diagram editor, "\
           + " then wait for the user to save the diagram (if edit command is enabled) before generating latex which is then inserted in the file after the line.")
    print("The edited diagram is also saved either as a json encoded diagram or in the specified filename")
    

    exit(0)




options = webdriver.FirefoxOptions()
options.unhandled_prompt_behavior = 'ignore'
browser = None 

def ctrlKey(actions,key):
    return actions.key_down(Keys.CONTROL).send_keys(key).key_up(Keys.CONTROL)




def parseMagic(line):
    searchPrefix = r"^(.*)" + MAGIC_STRING + r" *'([nge]+)"
    search = re.search(searchPrefix + r" +(.*)$", line)
    if not search:
        # in this case, content is empty
        search = re.search(searchPrefix + r"(.*)$", line)

    if search:
        prefix = search.group(1)
        command = search.group(2)
        content = search.group(3)
        return Command(content=content, prefix=prefix, command=command)
    else:
        return None

def listDiags(filename):
    # Opening file
    file = open(filename, 'r')
    diags = []
# Closing files

    for line in file:           
           search = parseMagic(line)
           
           if search:               
               command = search.command
               content = search.content               
               diags.append(Diag(content= content,
                  # prefix = prefix,
                  isFile = len(content) > 0 and (content[0] != '{'),
                  isEdit = 'e' in command or 'n' in command,
                  isNew = 'n' in command,
                  isGenerate = 'g' in command
               ))         
    file.close()
    return diags

def loadEditor(diag):
  browser.get(URL_YADE)
  if (diag.strip() == ""):
      print("Creating new diagram")
      browser.find_element(By.XPATH, '//button[text()="Clear"]').click()
  else:
      print("Loading diagram ")
      cmd = 'sendGraphToElm('+ diag + ", 'python');"
      browser.execute_script(cmd)
def waitSaveDiag():
    # we unsubscribe the implemented saveGraph procedure 
  browser.execute_script("app.ports.saveGraph.unsubscribe(saveGraph);")
  # browser.execute_script('var

  print("Save to continue")  
  # graph = None: it may be that the script was interrupted because
  # of a modal dialog box
  cmd =  "var mysave = function(a) {  window.saveSelenium(JSON.stringify(fromElmGraph(a))); } ;" 
  cmd = cmd + 'app.ports.saveGraph.subscribe(mysave);'
  browser.execute_script(cmd)

  cmd = "window.saveSelenium = arguments[arguments.length - 1]; "
  graph = None
  while graph == None:
    try:
        graph = browser.execute_async_script(cmd)
    except UnexpectedAlertPresentException:
        continue
  return graph

def genLatex():
  print("Exporting to latex")
  # Restoring the usual saveGraph procedure
  browser.execute_script("app.ports.saveGraph.subscribe(saveGraph);")
  
  canvas = browser.find_element(By.ID, "canvas")
  canvas.click()
  actions = ActionChains(browser)
  actions.move_to_element(canvas).move_by_offset(10,10).perform()
  ctrlKey(actions,'a').perform()
  browser.find_element(By.XPATH, '//button[text()="Export selection to quiver"]').click()
  # switch to new tab
  browser.switch_to.window(browser.window_handles[1])
  
  WebDriverWait(browser, 5).until(EC.invisibility_of_element((By.CSS_SELECTOR, "div.loading-screen")))
  el=WebDriverWait(browser, 5).until(EC.element_to_be_clickable((By.CSS_SELECTOR,"button[title='LaTeX']")))
  WebDriverWait(browser, 5).until(EC.invisibility_of_element((By.CSS_SELECTOR, "div.loading-screen")))
  el.click()
  el=WebDriverWait(browser, 5).until(EC.presence_of_element_located((By.CSS_SELECTOR,"div.code")))
  latex = el.text
  return latex
    
# return the json-encoded graph and the generated latex
def handleDiag(diag):
    global browser
    if diag.isFile:        
        fileName = diag.content
    content = diag.content
    if diag.isNew:
        
        if diag.isFile:
            if exists(fileName):
                print("Aborting diagram creation: File %s already exists." % fileName)
                exit(0)
        else:
            if content != "":
                print("Aborting diagram creation: data already provided (%s)." % content)
                exit(0)
    else:
        if diag.isFile:
           if not exists(fileName):
              print("Aborting diagram editing: file %s not found." % fileName)
              exit(0)
           
           file = open(fileName,mode='r')
           content = file.read()
           file.close()
        else:
            if content == "":
                print("Aborting diagram editing: no data provided.")
        
    
    

    # we only launch firefox once, if needed
    if browser == None:    
      browser = webdriver.Firefox(options=options)
      # long timeout for execute_async_script
      browser.set_script_timeout(84000)


    loadEditor(content)
    latex = None
    if diag.isEdit:
       content = waitSaveDiag()
    if diag.isGenerate:
       latex = genLatex()
    return (content, latex)

            



# does what is said in the help message
def remakeDiags(fileName):
    
    
    while True:
       diags = listDiags(fileName)
       if (len(diags) == 0):
          print("No diagram command found.")
          break
       print("%d diagram command(s) found" % len(diags))
       diag = diags[0]
       
       print("Handling a diagram")
       if not diag.isEdit:
          print("- No user editing")
       if diag.isGenerate:
          print("- Latex generation")
       if diag.isFile:
          print("- filename : " + diag.content)
       #print(diag)
       #exit(0)
       (graph, latex) = handleDiag(diag)

       if diag.isFile:
           fileName = diag.content
           print("Writing to file " + fileName)
           f = open(fileName, "w")
           f.write(graph)
           f.close()

       with in_place.InPlace(filename) as fp:           
            done = False
            for line in fp:
                if done:
                    fp.write(line)
                else:
                    search = parseMagic(line)
                    if search == None:
                        fp.write(line)
                    else:
                        done = True
                        suffix = diag.content if diag.isFile else graph
                        fp.write(search.prefix + MAGIC_STRING + " " + suffix + "\n")
                        if diag.isGenerate:
                            fp.write("\n% GENERATED LATEX\n")
                            fp.write(latex)
                            fp.write("\n% END OF GENERATED LATEX\n")
        


filename = sys.argv[1]
remakeDiags(filename)