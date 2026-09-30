from pathlib import Path
import plistlib, subprocess, shutil
root = Path(__file__).resolve().parent
src = root/'Source'
app = root/'Build/右键小工具.app'
ext = app/'Contents/PlugIns/RightClickFinder.appex'
shutil.copytree(root/'Templates', app/'Contents/Resources/Templates', dirs_exist_ok=True)
for bundle in [app, ext]: (bundle/'Contents/MacOS').mkdir(parents=True, exist_ok=True)
base = {'CFBundleDevelopmentRegion':'zh_CN','CFBundleVersion':'210','CFBundleShortVersionString':'2.1','LSMinimumSystemVersion':'13.0'}
info = base | {'CFBundleIdentifier':'local.suxin.rightclicktools','CFBundleName':'右键小工具','CFBundleDisplayName':'右键小工具','CFBundleExecutable':'RightClickTools','CFBundlePackageType':'APPL','NSPrincipalClass':'NSApplication','NSHighResolutionCapable':True,'LSUIElement':True,'CFBundleURLTypes':[{'CFBundleURLName':'RightClickTools actions','CFBundleURLSchemes':['local-rightclick-tools']}]}
einfo = base | {'CFBundleIdentifier':'local.suxin.rightclicktools.finder','CFBundleName':'右键小工具','CFBundleDisplayName':'右键小工具','CFBundleExecutable':'RightClickFinder','CFBundlePackageType':'XPC!','NSExtension':{'NSExtensionPointIdentifier':'com.apple.FinderSync','NSExtensionPrincipalClass':'FinderSync'}}
for bundle, value in [(app,info),(ext,einfo)]:
    with (bundle/'Contents/Info.plist').open('wb') as f: plistlib.dump(value,f)
ent = root/'Source/Finder.entitlements'
with ent.open('wb') as f: plistlib.dump({'com.apple.security.app-sandbox':True},f)
common = ['xcrun','swiftc','-swift-version','5','-module-cache-path',str(root/'Cache'),'-O','-target','arm64-apple-macosx13.0']
subprocess.run(common + [str(src/'Core.swift'),str(src/'main.swift'),'-o',str(app/'Contents/MacOS/RightClickTools'),'-framework','Cocoa','-framework','FinderSync'],check=True)
subprocess.run(common + ['-parse-as-library','-emit-executable','-module-name','RightClickFinder',str(src/'Core.swift'),str(src/'FinderSync.swift'),'-o',str(ext/'Contents/MacOS/RightClickFinder'),'-framework','Cocoa','-framework','FinderSync','-Xlinker','-e','-Xlinker','_NSExtensionMain'],check=True)
subprocess.run(['codesign','--force','--sign','-','--entitlements',str(ent),str(ext)],check=True)
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
print(app)
